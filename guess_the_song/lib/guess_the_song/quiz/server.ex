defmodule GuessTheSong.Quiz.Server do
  use GenServer, restart: :transient

  alias Nostrum.Api.Message
  alias GuessTheSong.Api
  alias GuessTheSong.Quiz.Track

  # How long to wait in the lobby before auto-starting (milliseconds)
  @lobby_timeout_ms 60_000

  # How long a round lasts before it ends automatically (Deezer previews are 30s)
  @round_duration_ms 31_000

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

  @spec get_random_track(guild_id :: integer) ::
          {:ok, {discord_id :: integer, lastfm :: Api.Lastfm.User.t(), track :: integer}}
          | {:error, :no_tracks}
  def get_random_track(guild_id), do: GenServer.call(via(guild_id), :get_random_track)

  @spec add_source(
          guild_id :: integer,
          discord_id :: integer,
          lastfm :: Api.Lastfm.User.t(),
          count :: integer
        ) :: :ok
  def add_source(guild_id, discord_id, lastfm, count),
    do: GenServer.cast(via(guild_id), {:add_source, {discord_id, lastfm, count}})

  @spec remove_source(guild_id :: integer, discord_id :: integer) :: :ok
  def remove_source(guild_id, discord_id),
    do: GenServer.cast(via(guild_id), {:remove_source, discord_id})

  @spec start_round(guild_id :: integer, track :: Track.t()) :: :ok
  def start_round(guild_id, track), do: GenServer.cast(via(guild_id), {:start_round, track})

  @spec end_round(guild_id :: integer) :: :ok
  def end_round(guild_id), do: GenServer.cast(via(guild_id), {:end_round})

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
             initiator_id: interaction.member.user_id
           },
           info: %{
             guild_id: guild_id,
             text_channel_id: text_channel_id,
             voice_channel_id: voice_channel_id,
             quiz_pid: nil,
             rounds: rounds,
             tracks_per_user: tracks_per_user,
             period: period
           },
           round: %{
             number: 0,
             running: false,
             track: nil
           },
           sources: %{},
           scores: %{}
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

      true ->
        new_opted_in = MapSet.put(state.lobby.opted_in, discord_id)
        state = put_in(state, [:lobby, :opted_in], new_opted_in)
        update_lobby_embed(state)
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
  def handle_call(:get_random_track, _from, state) do
    # Only pick from sources that still have unplayed tracks
    available = Enum.filter(state.sources, fn {_, source} -> MapSet.size(source.choices) > 0 end)

    case available do
      [] ->
        {:reply, {:error, :no_tracks}, state}

      _ ->
        {discord_id, source} = Enum.random(available)
        track = Enum.random(source.choices)

        new_state =
          update_in(state, [:sources, discord_id, :choices], &(&1 |> MapSet.delete(track)))

        {:reply, {:ok, {discord_id, source.lastfm, track}}, new_state}
    end
  end

  @impl true
  def handle_cast({:add_source, {discord_id, lastfm, count}}, state) do
    {:noreply,
     update_in(
       state.sources,
       &Map.put(&1, discord_id, %{lastfm: lastfm, choices: MapSet.new(1..count)})
     )}
  end

  @impl true
  def handle_cast({:remove_source, discord_id}, state) do
    {:noreply, update_in(state.sources, &Map.delete(&1, discord_id))}
  end

  @impl true
  def handle_cast({:start_round, track}, state) do
    if state.round.running do
      {:noreply, state}
    else
      number = state.round.number + 1
      timer_ref = Process.send_after(self(), {:round_timeout, number}, @round_duration_ms)

      new_round = %{
        track: track,
        number: number,
        running: true,
        scores: %{},
        timer_ref: timer_ref
      }

      {:noreply, put_in(state, [:round], new_round)}
    end
  end

  def handle_cast({:end_round}, state) do
    if state.round.running do
      Process.cancel_timer(state.round.timer_ref)

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

      send(state.info.quiz_pid, {:round_ended})
      {:noreply, put_in(state, [:round, :running], false)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:process_message, msg}, %{round: %{running: true}} = state) do
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
      GuessTheSong.Quiz.Server.end_round(new_state.info.guild_id)
    end

    {:noreply, new_state}
  end

  # Ignore messages when the round is not running
  def handle_cast({:process_message, _msg}, %{round: %{running: false}} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:lobby_timeout, %{phase: :lobby} = state) do
    case launch_quiz(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, :no_players, _state} -> {:stop, :normal, state}
    end
  end

  # Only end the round if the timeout belongs to the current round
  @impl true
  def handle_info({:round_timeout, number}, %{round: %{number: number, running: true}} = state) do
    GuessTheSong.Quiz.Server.end_round(state.info.guild_id)
    {:noreply, state}
  end

  def handle_info({:round_timeout, _number}, state), do: {:noreply, state}

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    IO.puts("Quiz ended normally")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    IO.inspect(reason)

    Message.create(state.info.text_channel_id,
      embed: GuessTheSong.Quiz.Embeds.error("Oops. Something went wrong running the quiz :(")
    )

    {:stop, :normal, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp update_lobby_embed(state) do
    opted_in_users =
      Enum.filter(state.lobby.eligible, fn u ->
        MapSet.member?(state.lobby.opted_in, u.discord_id)
      end)

    Nostrum.Api.Interaction.edit_response(state.lobby.interaction, %{
      type: 7,
      embeds: [
        GuessTheSong.Quiz.Embeds.lobby(state.lobby.eligible, @lobby_timeout_ms, opted_in_users)
      ],
      components: GuessTheSong.Quiz.Embeds.lobby_components()
    })
  end

  defp launch_quiz(%{phase: :lobby} = state) do
    interaction = state.lobby.interaction
    opted_in = state.lobby.opted_in
    info = state.info

    opted_in_users =
      Enum.filter(state.lobby.eligible, fn u ->
        MapSet.member?(opted_in, u.discord_id)
      end)

    case opted_in_users do
      [] ->
        Nostrum.Api.Interaction.edit_response(interaction, %{
          type: 7,
          embeds: [GuessTheSong.Quiz.Embeds.error("Nobody joined the lobby — quiz cancelled.")],
          components: []
        })

        {:error, :no_players, state}

      participants ->
        pid =
          spawn_link(fn ->
            # Skip any players whose Last.fm library couldn't be loaded
            sources =
              Enum.filter(participants, fn user ->
                case GuessTheSong.Quiz.add_source(
                       info.guild_id,
                       user.discord_id,
                       user.lastfm_username,
                       info.tracks_per_user
                     ) do
                  :ok ->
                    true

                  {:error, reason} ->
                    IO.inspect(reason, label: "Failed to add source #{user.lastfm_username}")
                    false
                end
              end)

            case sources do
              [] ->
                Nostrum.Api.Interaction.edit_response(interaction, %{
                  type: 7,
                  embeds: [GuessTheSong.Quiz.Embeds.error("Couldn't load any Last.fm libraries")],
                  components: []
                })

              _ ->
                case GuessTheSong.Voice.Supervisor.start_session(
                       info.guild_id,
                       info.voice_channel_id
                     ) do
                  {:ok, _pid} ->
                    Nostrum.Api.Interaction.edit_response(interaction, %{
                      type: 7,
                      embeds: [GuessTheSong.Quiz.Embeds.starting(sources)],
                      components: []
                    })

                    GuessTheSong.Quiz.run_quiz(
                      info.guild_id,
                      info.text_channel_id,
                      info.rounds,
                      info.period
                    )

                  {:error, :already_active} ->
                    Nostrum.Api.Interaction.edit_response(interaction, %{
                      type: 7,
                      embeds: [GuessTheSong.Quiz.Embeds.error("Bot is already in a voice channel")],
                      components: []
                    })
                end
            end
          end)

        new_state =
          state
          |> Map.put(:phase, :running)
          |> Map.delete(:lobby)
          |> put_in([:info, :quiz_pid], pid)

        {:ok, new_state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    IO.puts("Terminating GameServer for guild_id: #{state.info.guild_id}")

    if map_size(state.scores) > 0 do
      Nostrum.Api.Message.create(state.info.text_channel_id,
        embed: GuessTheSong.Quiz.Embeds.game_end(state.scores)
      )
    end

    GuessTheSong.Voice.Supervisor.stop_session(state.info.guild_id)
  end
end
