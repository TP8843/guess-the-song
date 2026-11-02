defmodule GuessTheSong.Quiz.Server do
  # Not restarted after a crash, since `init` would repost the lobby using the
  # original interaction. `terminate` tells the players instead.
  use GenServer, restart: :temporary

  alias GuessTheSong.Quiz.Sender

  # How long to wait in the lobby before auto-starting (milliseconds)
  @lobby_timeout_ms 60_000

  # How long to wait after a join before updating the lobby message, so joins
  # close together share one edit
  @lobby_refresh_ms 1_000

  # How long lobby button calls wait for the server. Discord needs a reply to a
  # button click within 3 seconds, so this leaves time to send one.
  @button_call_timeout_ms 2_000

  # How long a round lasts before it ends automatically (Deezer previews are 30s)
  @round_duration_ms 31_000

  # How many tracks to try before giving up on finding a Deezer match for a round
  @max_track_attempts 5

  # How long to wait for one player's Last.fm library before skipping them
  @source_load_timeout_ms 60_000

  def start_link(
        {interaction, guild_id, text_channel_id, voice_channel_id, rounds, tracks_per_user,
         period}
      ) do
    GenServer.start_link(
      __MODULE__,
      {interaction, guild_id, text_channel_id, voice_channel_id, rounds, tracks_per_user, period},
      name:
        {:via, Registry,
         {GuessTheSong.Quiz.Registry, guild_id, %{text_channel_id: text_channel_id}}}
    )
  end

  def get_info(guild_id), do: GenServer.call(via(guild_id), :get_info)

  def get_source(guild_id, discord_id),
    do: GenServer.call(via(guild_id), {:get_source, discord_id})

  @spec join_lobby(guild_id :: integer, discord_id :: integer) :: :ok | {:error, atom()}
  def join_lobby(guild_id, discord_id),
    do: safe_call(guild_id, {:join_lobby, discord_id})

  @spec start_now(guild_id :: integer, discord_id :: integer) :: :ok | {:error, atom()}
  def start_now(guild_id, discord_id),
    do: safe_call(guild_id, {:start_now, discord_id})

  @spec process_message(guild_id :: integer, msg :: Nostrum.Struct.Message.t()) :: :ok
  def process_message(guild_id, msg), do: GenServer.cast(via(guild_id), {:process_message, msg})

  @spec stop(guild_id :: integer) :: :ok
  def stop(guild_id) do
    GenServer.stop(via(guild_id))
  catch
    # Quiz already stopped (e.g. two /end-quiz commands at once)
    :exit, _ -> :ok
  end

  defp via(guild_id) do
    {:via, Registry, {GuessTheSong.Quiz.Registry, guild_id}}
  end

  # Calls the quiz server, returning an error instead of exiting if it stops
  # before or during the call (e.g. a button clicked just as the quiz ends).
  # A timeout means the quiz is still running but slow to reply, and it may
  # still handle the request after we give up.
  defp safe_call(guild_id, message) do
    GenServer.call(via(guild_id), message, @button_call_timeout_ms)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :not_active}
  end

  @impl true
  def init(
        {interaction, guild_id, text_channel_id, voice_channel_id, rounds, tracks_per_user,
         period}
      ) do
    IO.puts(
      "Starting QuizServer for guild_id: #{guild_id} and text_channel_id: #{text_channel_id} and voice_channel_id: #{voice_channel_id} and rounds: #{rounds} and tracks_per_user: #{tracks_per_user} and period: #{period}"
    )

    # So `terminate` runs (leaving voice, posting scores) when the app shuts down
    Process.flag(:trap_exit, true)

    # Fetch voice-channel members who have a linked Last.fm account
    eligible = GuessTheSong.Quiz.eligible_users(guild_id, voice_channel_id)

    case eligible do
      [] ->
        Nostrum.Api.Interaction.edit_response(interaction, %{
          type: 7,
          embeds: [
            GuessTheSong.Quiz.Embeds.error("No users with linked accounts in voice channel")
          ]
        })

        {:stop, :no_sources}

      _ ->
        # Send the lobby embed and start the countdown timer
        timer_ref = Process.send_after(self(), :lobby_timeout, @lobby_timeout_ms)

        Nostrum.Api.Interaction.edit_response(interaction, %{
          type: 7,
          embeds: [GuessTheSong.Quiz.Embeds.lobby(eligible, @lobby_timeout_ms)],
          components: GuessTheSong.Quiz.Embeds.lobby_components()
        })

        {:ok, sender} = Sender.start(self())

        {:ok,
         %{
           phase: :lobby,
           # Posts this quiz's channel messages, so the quiz never waits on Discord
           sender: sender,
           lobby: %{
             interaction: interaction,
             eligible: eligible,
             opted_in: MapSet.new(),
             timer_ref: timer_ref,
             initiator_id: interaction.member.user_id,
             # Whether a `:refresh_lobby` is scheduled
             refresh_pending: false,
             # Task editing the lobby message, if one has been started
             refresh_task: nil
           },
           info: %{
             guild_id: guild_id,
             text_channel_id: text_channel_id,
             voice_channel_id: voice_channel_id,
             rounds: rounds,
             tracks_per_user: tracks_per_user,
             period: period
           },
           round: %{
             number: 0,
             track: nil
           },
           sources: %{},
           scores: %{},
           # Background task for slow work (e.g. loading Last.fm libraries)
           task: nil,
           # Result of fetching the next round's track during the current round
           # (`{:ok, track}` or `{:error, reason}`), until the next round uses it
           next_track: nil,
           # Monitors the voice session, so the quiz ends if it stops
           voice_ref: nil
         }}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply, state.info, state}
  end

  @impl true
  def handle_call({:join_lobby, discord_id}, _from, %{phase: :lobby} = state) do
    eligible_ids = Enum.map(state.lobby.eligible, & &1.discord_id)

    cond do
      discord_id not in eligible_ids ->
        {:reply, {:error, :not_eligible}, state}

      MapSet.member?(state.lobby.opted_in, discord_id) ->
        {:reply, {:error, :already_joined}, state}

      # Reply straight away and update the lobby message later, since Discord
      # needs the button click answered within 3 seconds
      true ->
        new_opted_in = MapSet.put(state.lobby.opted_in, discord_id)

        state =
          state
          |> put_in([:lobby, :opted_in], new_opted_in)
          |> schedule_lobby_refresh()

        {:reply, :ok, state}
    end
  end

  def handle_call({:join_lobby, _discord_id}, _from, state) do
    {:reply, {:error, :not_in_lobby}, state}
  end

  @impl true
  def handle_call({:start_now, discord_id}, _from, %{phase: :lobby} = state) do
    if discord_id == state.lobby.initiator_id do
      Process.cancel_timer(state.lobby.timer_ref)

      case launch_quiz(state) do
        {:ok, new_state} -> {:reply, :ok, new_state}
        {:error, :no_players, new_state} -> {:stop, :normal, {:error, :no_players}, new_state}
      end
    else
      {:reply, {:error, :not_initiator}, state}
    end
  end

  def handle_call({:start_now, _discord_id}, _from, state) do
    {:reply, {:error, :not_in_lobby}, state}
  end

  @impl true
  def handle_call({:get_source, discord_id}, _from, state) do
    {:reply, state.sources[discord_id], state}
  end

  @impl true
  def handle_cast({:process_message, msg}, %{phase: :playing} = state) do
    alias GuessTheSong.Quiz.Track.GuessElement

    # Every part of the track this message guesses that nobody has got yet
    matched =
      Enum.filter(state.round.track.guess_elements, fn element ->
        not element.guessed and GuessElement.match?(element, msg.content)
      end)

    case matched do
      [] ->
        {:noreply, state}

      _ ->
        state = mark_guessed(state, matched, msg.author.id)

        # One reply for everything this message got right
        Sender.post(state.sender, state.info.text_channel_id,
          embed: GuessTheSong.Quiz.Embeds.correct_guesses(matched),
          message_reference: %{message_id: msg.id}
        )

        if Enum.all?(state.round.track.guess_elements, & &1.guessed) do
          end_round(state)
        else
          {:noreply, state}
        end
    end
  end

  # Ignore messages when a round isn't playing
  def handle_cast({:process_message, _msg}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:lobby_timeout, %{phase: :lobby} = state) do
    case launch_quiz(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, :no_players, _state} -> {:stop, :normal, state}
    end
  end

  # Timer fired just as the quiz was started manually
  def handle_info(:lobby_timeout, state), do: {:noreply, state}

  # Edits the lobby message in a task, so the server never waits on Discord
  def handle_info(:refresh_lobby, %{phase: :lobby} = state) do
    lobby = state.lobby

    if lobby.refresh_task && Process.alive?(lobby.refresh_task.pid) do
      # The last edit is still waiting on Discord, so try again shortly rather
      # than risk the edits arriving out of order
      Process.send_after(self(), :refresh_lobby, @lobby_refresh_ms)
      {:noreply, state}
    else
      task =
        Task.Supervisor.async_nolink(GuessTheSong.Quiz.TaskSupervisor, fn ->
          update_lobby_embed(lobby)
        end)

      {:noreply, %{state | lobby: %{lobby | refresh_pending: false, refresh_task: task}}}
    end
  end

  # The quiz started before the refresh was due
  def handle_info(:refresh_lobby, state), do: {:noreply, state}

  # Only end the round if the timeout belongs to the current round
  @impl true
  def handle_info({:round_timeout, number}, %{phase: :playing, round: %{number: number}} = state) do
    end_round(state)
  end

  def handle_info({:round_timeout, _number}, state), do: {:noreply, state}

  def handle_info(:next_round, %{phase: :between_rounds} = state), do: next_round(state)
  def handle_info(:next_round, state), do: {:noreply, state}

  # Voice is connected, so start the first round
  def handle_info(:voice_ready, %{phase: :joining} = state) do
    next_round(Map.delete(state, :lobby))
  end

  def handle_info(:voice_ready, state), do: {:noreply, state}

  # Last.fm libraries finished loading, so join voice
  @impl true
  def handle_info({ref, loaded}, %{phase: :loading, task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | task: nil}
    info = state.info

    with [_ | _] <- loaded,
         {:ok, voice_pid} <-
           GuessTheSong.Voice.Supervisor.start_session(
             info.guild_id,
             info.voice_channel_id,
             self()
           ) do
      Nostrum.Api.Interaction.edit_response(state.lobby.interaction, %{
        type: 7,
        embeds: [GuessTheSong.Quiz.Embeds.starting(Enum.map(loaded, &elem(&1, 0)))],
        components: []
      })

      sources =
        Map.new(loaded, fn {_user, {discord_id, lastfm, tracks}} ->
          {discord_id, %{lastfm: lastfm, choices: tracks}}
        end)

      # Wait for `:voice_ready` before playing anything
      {:noreply,
       %{
         state
         | phase: :joining,
           sources: sources,
           voice_ref: Process.monitor(voice_pid)
       }}
    else
      [] ->
        loading_failed(state, "Couldn't load any Last.fm libraries")

      {:error, :already_active} ->
        loading_failed(state, "Bot is already in a voice channel")

      {:error, reason} ->
        IO.inspect(reason, label: "Failed to join voice channel")
        loading_failed(state, "Couldn't join the voice channel")
    end
  end

  # The loading task crashed
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{phase: :loading, task: %Task{ref: ref}} = state
      ) do
    IO.inspect(reason, label: "Loading task crashed")
    loading_failed(%{state | task: nil}, "Oops. Something went wrong starting the quiz :(")
  end

  # A track finished fetching. This can be while a round waits on it
  # (`:fetching`), or early, during the previous round.
  def handle_info({ref, {attempts, result}}, %{phase: phase, task: %Task{ref: ref}} = state)
      when phase in [:fetching, :playing, :between_rounds] do
    Process.demonitor(ref, [:flush])
    state = %{state | task: nil}

    case result do
      # Track missing on Deezer, so try a different one
      {:error, :not_found} -> start_fetch(state, attempts + 1)
      result -> track_fetched(state, result)
    end
  end

  # The fetch task crashed, so that round will be skipped
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{phase: phase, task: %Task{ref: ref}} = state
      )
      when phase in [:fetching, :playing, :between_rounds] do
    track_fetched(%{state | task: nil}, {:error, {:fetch_crashed, reason}})
  end

  # The voice session stopped (e.g. it timed out waiting to connect)
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{voice_ref: ref} = state) do
    IO.inspect(reason, label: "Voice session stopped")
    state = %{state | voice_ref: nil}

    case state.phase do
      :joining ->
        loading_failed(state, "Couldn't join the voice channel")

      _ ->
        Sender.post(state.sender, state.info.text_channel_id,
          embed:
            GuessTheSong.Quiz.Embeds.error("Lost the voice connection, so the quiz has ended")
        )

        {:stop, :normal, state}
    end
  end

  # Ignore results from tasks that are no longer current
  def handle_info({ref, _result}, state) when is_reference(ref), do: {:noreply, state}
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Schedules a lobby message update, unless one is already scheduled
  defp schedule_lobby_refresh(%{lobby: %{refresh_pending: true}} = state), do: state

  defp schedule_lobby_refresh(state) do
    Process.send_after(self(), :refresh_lobby, @lobby_refresh_ms)
    put_in(state, [:lobby, :refresh_pending], true)
  end

  # Runs in a task (see the `:refresh_lobby` handler)
  defp update_lobby_embed(lobby) do
    opted_in_users =
      Enum.filter(lobby.eligible, fn u ->
        MapSet.member?(lobby.opted_in, u.discord_id)
      end)

    Nostrum.Api.Interaction.edit_response(lobby.interaction, %{
      type: 7,
      embeds: [
        GuessTheSong.Quiz.Embeds.lobby(lobby.eligible, @lobby_timeout_ms, opted_in_users)
      ],
      components: GuessTheSong.Quiz.Embeds.lobby_components()
    })
  end

  # Marks the matched parts as guessed by this user, and adds their points to
  # the round scores
  defp mark_guessed(state, matched, user_id) do
    points = matched |> Enum.map(& &1.value) |> Enum.sum()

    state
    |> update_in([:round, :track], fn track ->
      elements =
        Enum.map(track.guess_elements, fn element ->
          if element in matched,
            do: %{element | guessed: true, guessed_by: user_id},
            else: element
        end)

      %{
        track
        | guess_elements: elements,
          correct_guesses: track.correct_guesses + length(matched)
      }
    end)
    |> update_in(
      [:round, :scores],
      &Map.update(&1, user_id, points, fn score -> score + points end)
    )
  end

  # Picks a random unplayed track and removes it from its source's choices
  defp pick_track(state) do
    # Only pick from sources that still have unplayed tracks
    available = Enum.filter(state.sources, fn {_, source} -> source.choices != [] end)

    case available do
      [] ->
        {:error, :no_tracks}

      _ ->
        {discord_id, source} = Enum.random(available)

        {track, remaining} =
          List.pop_at(source.choices, :rand.uniform(length(source.choices)) - 1)

        new_state = put_in(state, [:sources, discord_id, :choices], remaining)

        {:ok, {discord_id, source.lastfm, track}, new_state}
    end
  end

  # Starts the next round, or ends the quiz after the last one
  defp next_round(state) do
    cond do
      state.round.number >= state.info.rounds ->
        {:stop, :normal, state}

      # Fetched during the previous round
      state.next_track != nil ->
        use_track(%{state | next_track: nil}, state.next_track)

      # Still being fetched, so wait for it (see `track_fetched/2`)
      state.task != nil ->
        {:noreply, %{state | phase: :fetching}}

      # Nothing fetched yet (e.g. the first round)
      true ->
        start_fetch(%{state | phase: :fetching}, 0)
    end
  end

  # Picks a track and starts fetching it, giving up after too many missing
  # tracks. Leaves the phase alone, so it works both for a round waiting on
  # the track (`:fetching`) and for fetching ahead during a round.
  defp start_fetch(state, attempts) when attempts >= @max_track_attempts do
    track_fetched(state, {:error, :no_match})
  end

  defp start_fetch(state, attempts) do
    case pick_track(state) do
      {:ok, {_discord_id, lastfm, lastfm_track}, state} ->
        task =
          Task.Supervisor.async_nolink(GuessTheSong.Quiz.TaskSupervisor, fn ->
            {attempts, GuessTheSong.Quiz.fetch_track(lastfm, lastfm_track)}
          end)

        {:noreply, %{state | task: task}}

      {:error, :no_tracks} ->
        track_fetched(state, {:error, :no_tracks})
    end
  end

  # A round is waiting on this track, so use it now
  defp track_fetched(%{phase: :fetching} = state, result), do: use_track(state, result)

  # Fetched early, so keep it until the next round starts
  defp track_fetched(state, result), do: {:noreply, %{state | next_track: result}}

  defp use_track(state, {:ok, track}), do: start_round(state, track)
  # Every source has run out of tracks, so end the quiz early
  defp use_track(state, {:error, :no_tracks}), do: {:stop, :normal, state}
  defp use_track(state, {:error, reason}), do: skip_round(state, reason)

  # Counts the round as played without playing anything, then moves on
  defp skip_round(state, reason) do
    IO.inspect(reason, label: "Skipping round")
    next_round(update_in(state, [:round, :number], &(&1 + 1)))
  end

  defp start_round(state, track) do
    play_track(state.info.guild_id, track)

    number = state.round.number + 1
    timer_ref = Process.send_after(self(), {:round_timeout, number}, @round_duration_ms)

    new_round = %{
      track: track,
      number: number,
      scores: %{},
      timer_ref: timer_ref
    }

    state = %{state | phase: :playing, round: new_round}

    if number < state.info.rounds do
      # Fetch the next round's track while this one plays
      start_fetch(state, 0)
    else
      {:noreply, state}
    end
  end

  # Doesn't wait for playback to start. Failures are logged by `Voice.Server`,
  # and a stopped voice session is handled by the `:DOWN` handler.
  defp play_track(guild_id, track) do
    GuessTheSong.Voice.Server.play_audio(guild_id, track.deezer.preview, :url, volume: 0.4)
  end

  defp end_round(state) do
    Process.cancel_timer(state.round.timer_ref)
    GuessTheSong.Voice.Server.stop_audio(state.info.guild_id)

    state =
      update_in(
        state,
        [:scores],
        &Enum.reduce(state.round.scores, &1, fn {user_id, score}, acc ->
          Map.update(acc, user_id, score, fn value ->
            value + score
          end)
        end)
      )

    Sender.post(state.sender, state.info.text_channel_id,
      content: "Round End",
      embed:
        GuessTheSong.Quiz.Embeds.round_end(
          state.round.track,
          state.round.scores,
          state.scores
        )
    )

    if state.round.number >= state.info.rounds do
      {:stop, :normal, state}
    else
      # Short pause before the next round's audio
      Process.send_after(self(), :next_round, 1000)
      {:noreply, %{state | phase: :between_rounds}}
    end
  end

  defp launch_quiz(%{phase: :lobby} = state) do
    interaction = state.lobby.interaction
    opted_in = state.lobby.opted_in
    info = state.info

    # Cancel any lobby edit that hasn't been sent yet, so it can't overwrite
    # the message below
    if state.lobby.refresh_task, do: Task.shutdown(state.lobby.refresh_task, :brutal_kill)

    opted_in_users =
      Enum.filter(state.lobby.eligible, fn u ->
        MapSet.member?(opted_in, u.discord_id)
      end)

    case opted_in_users do
      [] ->
        # In a task, so a "Start Now" click is answered without waiting on Discord
        Task.Supervisor.start_child(GuessTheSong.Quiz.TaskSupervisor, fn ->
          Nostrum.Api.Interaction.edit_response(interaction, %{
            type: 7,
            embeds: [
              GuessTheSong.Quiz.Embeds.error("Nobody joined the lobby — quiz cancelled.")
            ],
            components: []
          })
        end)

        {:error, :no_players, state}

      participants ->
        tracks_per_user = info.tracks_per_user
        period = info.period

        task =
          Task.Supervisor.async_nolink(GuessTheSong.Quiz.TaskSupervisor, fn ->
            load_sources(participants, tracks_per_user, period)
          end)

        {:ok, %{state | phase: :loading, task: task}}
    end
  end

  # Runs in a task. Returns `{user, source}` for each player whose Last.fm
  # library loaded, skipping the rest. Players load in parallel, since a full
  # 1000-track library takes a few seconds to fetch.
  defp load_sources(participants, tracks_per_user, period) do
    participants
    |> Task.async_stream(
      fn user ->
        GuessTheSong.Quiz.load_source(
          user.discord_id,
          user.lastfm_username,
          tracks_per_user,
          period
        )
      end,
      max_concurrency: 4,
      timeout: @source_load_timeout_ms,
      on_timeout: :kill_task
    )
    |> Enum.zip(participants)
    |> Enum.flat_map(fn
      {{:ok, {:ok, source}}, user} ->
        [{user, source}]

      {{:ok, {:error, reason}}, user} ->
        IO.inspect(reason, label: "Failed to add source #{user.lastfm_username}")
        []

      {{:exit, reason}, user} ->
        IO.inspect(reason, label: "Failed to add source #{user.lastfm_username}")
        []
    end)
  end

  defp loading_failed(state, message) do
    Nostrum.Api.Interaction.edit_response(state.lobby.interaction, %{
      type: 7,
      embeds: [GuessTheSong.Quiz.Embeds.error(message)],
      components: []
    })

    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("Terminating GameServer for guild_id: #{state.info.guild_id}")

    # Don't leave a task running for a quiz that has ended
    if state.task, do: Task.shutdown(state.task, :brutal_kill)

    # Through the sender, so these come after any messages still queued (like
    # the last "Round End"). The sender sends them after this process stops.
    if crashed?(reason) do
      Sender.post(state.sender, state.info.text_channel_id,
        embed: GuessTheSong.Quiz.Embeds.error("Oops. Something went wrong running the quiz :(")
      )
    end

    if map_size(state.scores) > 0 do
      Sender.post(state.sender, state.info.text_channel_id,
        embed: GuessTheSong.Quiz.Embeds.game_end(state.scores)
      )
    end

    GuessTheSong.Voice.Supervisor.stop_session(state.info.guild_id)
  end

  defp crashed?(:normal), do: false
  defp crashed?(:shutdown), do: false
  defp crashed?({:shutdown, _}), do: false
  defp crashed?(_reason), do: true
end
