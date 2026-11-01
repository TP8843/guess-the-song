defmodule GuessTheSong.Quiz.Server do
  # Not restarted after a crash, since `init` would repost the lobby using the
  # original interaction. `terminate` tells the players instead.
  use GenServer, restart: :temporary

  alias Nostrum.Api.Message

  # How long to wait in the lobby before auto-starting (milliseconds)
  @lobby_timeout_ms 60_000

  # How long to wait after a join before updating the lobby message, so joins
  # close together share one edit
  @lobby_refresh_ms 1_000

  # How long a round lasts before it ends automatically (Deezer previews are 30s)
  @round_duration_ms 31_000

  # How many tracks to try before giving up on finding a Deezer match for a round
  @max_track_attempts 5

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
  # before or during the call (e.g. a button clicked just as the quiz ends)
  defp safe_call(guild_id, message) do
    GenServer.call(via(guild_id), message)
  catch
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

        {:ok,
         %{
           phase: :lobby,
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

    new_state =
      Enum.reduce(state.round.track.guess_elements, state, fn guess_element, acc ->
        if not guess_element.guessed and GuessElement.match?(guess_element, msg.content) do
          Nostrum.Api.Message.create(state.info.text_channel_id,
            embed: GuessTheSong.Quiz.Embeds.correct_guess(guess_element),
            message_reference: %{message_id: msg.id}
          )

          acc =
            update_in(acc, [:round, :track], fn track ->
              %{
                track
                | guess_elements:
                    Enum.map(track.guess_elements, fn element ->
                      if element == guess_element do
                        %{element | guessed: true, guessed_by: msg.author.id}
                      else
                        element
                      end
                    end)
              }
            end)

          acc =
            update_in(
              acc,
              [:round, :scores],
              &Map.update(&1, msg.author.id, guess_element.value, fn value ->
                value + guess_element.value
              end)
            )

          acc =
            update_in(acc, [:round, :track], fn track ->
              %{track | correct_guesses: track.correct_guesses + 1}
            end)

          acc
        else
          acc
        end
      end)

    if new_state.round.track.correct_guesses == length(new_state.round.track.guess_elements) do
      end_round(new_state)
    else
      {:noreply, new_state}
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
        Map.new(loaded, fn {_user, {discord_id, lastfm, count}} ->
          {discord_id, %{lastfm: lastfm, choices: MapSet.new(1..count)}}
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

  # A track finished fetching
  def handle_info({ref, {attempts, result}}, %{phase: :fetching, task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | task: nil}

    case result do
      {:ok, track} -> start_round(state, track)
      # Track missing on Last.fm or Deezer, so try a different one
      {:error, :not_found} -> fetch_next_track(state, attempts + 1)
      {:error, reason} -> skip_round(state, reason)
    end
  end

  # The fetch task crashed, so skip this round
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{phase: :fetching, task: %Task{ref: ref}} = state
      ) do
    skip_round(%{state | task: nil}, {:fetch_crashed, reason})
  end

  # The voice session stopped (e.g. it timed out waiting to connect)
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{voice_ref: ref} = state) do
    IO.inspect(reason, label: "Voice session stopped")
    state = %{state | voice_ref: nil}

    case state.phase do
      :joining ->
        loading_failed(state, "Couldn't join the voice channel")

      _ ->
        Message.create(state.info.text_channel_id,
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

  # Picks a random unplayed track and removes it from its source's choices
  defp pick_track(state) do
    # Only pick from sources that still have unplayed tracks
    available = Enum.filter(state.sources, fn {_, source} -> MapSet.size(source.choices) > 0 end)

    case available do
      [] ->
        {:error, :no_tracks}

      _ ->
        {discord_id, source} = Enum.random(available)
        track = Enum.random(source.choices)

        new_state =
          update_in(state, [:sources, discord_id, :choices], &(&1 |> MapSet.delete(track)))

        {:ok, {discord_id, source.lastfm, track}, new_state}
    end
  end

  # Starts the next round, or ends the quiz after the last one
  defp next_round(state) do
    if state.round.number >= state.info.rounds do
      {:stop, :normal, state}
    else
      fetch_next_track(state, 0)
    end
  end

  # Picks a track and starts fetching it, giving up after too many missing tracks
  defp fetch_next_track(state, attempts) when attempts >= @max_track_attempts do
    skip_round(state, :no_match)
  end

  defp fetch_next_track(state, attempts) do
    case pick_track(state) do
      {:ok, {_discord_id, lastfm, index}, state} ->
        period = state.info.period

        task =
          Task.Supervisor.async_nolink(GuessTheSong.Quiz.TaskSupervisor, fn ->
            {attempts, GuessTheSong.Quiz.fetch_track(lastfm, period, index)}
          end)

        {:noreply, %{state | phase: :fetching, task: task}}

      # Every source has run out of tracks, so end the quiz early
      {:error, :no_tracks} ->
        {:stop, :normal, state}
    end
  end

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

    {:noreply, %{state | phase: :playing, round: new_round}}
  end

  defp play_track(guild_id, track) do
    case GuessTheSong.Voice.Server.play_audio(guild_id, track.deezer.preview, :url, volume: 0.4) do
      :ok -> :ok
      {:error, reason} -> IO.inspect(reason, label: "Failed to play track")
    end
  catch
    # Voice session stopped, which the `:DOWN` handler deals with
    :exit, reason -> IO.inspect(reason, label: "Failed to play track")
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

    Nostrum.Api.Message.create(state.info.text_channel_id,
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

        task =
          Task.Supervisor.async_nolink(GuessTheSong.Quiz.TaskSupervisor, fn ->
            load_sources(participants, tracks_per_user)
          end)

        {:ok, %{state | phase: :loading, task: task}}
    end
  end

  # Runs in a task. Returns `{user, source}` for each player whose Last.fm
  # library loaded, skipping the rest.
  defp load_sources(participants, tracks_per_user) do
    Enum.flat_map(participants, fn user ->
      case GuessTheSong.Quiz.load_source(user.discord_id, user.lastfm_username, tracks_per_user) do
        {:ok, source} ->
          [{user, source}]

        {:error, reason} ->
          IO.inspect(reason, label: "Failed to add source #{user.lastfm_username}")
          []
      end
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

    if crashed?(reason) do
      Message.create(state.info.text_channel_id,
        embed: GuessTheSong.Quiz.Embeds.error("Oops. Something went wrong running the quiz :(")
      )
    end

    if map_size(state.scores) > 0 do
      Nostrum.Api.Message.create(state.info.text_channel_id,
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
