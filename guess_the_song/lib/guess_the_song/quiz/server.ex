defmodule GuessTheSong.Quiz.Server do
  use GenServer, restart: :transient

  alias Nostrum.Api.Message

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

  @spec get_random_track(guild_id :: integer) ::
          {discord_id :: integer, lastfm_id :: String.t(), track :: integer}
  def get_random_track(guild_id), do: GenServer.call(via(guild_id), :get_random_track)

  @spec add_source(
          guild_id :: integer,
          discord_id :: integer,
          lastfm :: Api.Lastfm.User.t(),
          count :: integer
        ) :: :ok
  def add_source(guild_id, discord_id, lastfm_id, count),
    do: GenServer.cast(via(guild_id), {:add_source, {discord_id, lastfm_id, count}})

  @spec remove_source(guild_id :: integer, discord_id :: integer) :: :ok
  def remove_source(guild_id, discord_id),
    do: GenServer.cast(via(guild_id), {:remove_source, discord_id})

  @spec start_round(guild_id :: integer, track :: Track.t()) :: :ok
  def start_round(guild_id, track), do: GenServer.cast(via(guild_id), {:start_round, track})

  @spec end_round(guild_id :: integer) :: :ok
  def end_round(guild_id), do: GenServer.cast(via(guild_id), {:end_round})

  @spec process_message(guild_id :: integer, msg :: Message.t()) :: :ok
  def process_message(guild_id, msg), do: GenServer.cast(via(guild_id), {:process_message, msg})

  @spec stop(guild_id :: integer) :: :ok
  def stop(guild_id), do: GenServer.stop(via(guild_id))

  defp via(guild_id) do
    {:via, Registry, {GuessTheSong.Quiz.Registry, guild_id}}
  end

  @impl true
  def init(
        {interaction, guild_id, text_channel_id, voice_channel_id, rounds, tracks_per_user,
         period}
      ) do
    IO.puts(
      "Starting QuizServer for guild_id: #{guild_id} and text_channel_id: #{text_channel_id} and voice_channel_id: #{voice_channel_id} and rounds: #{rounds} and tracks_per_user: #{tracks_per_user} and period: #{period}"
    )

    # Ensure that if the quiz process exits, the server is stopped
    Process.flag(:trap_exit, true)

    pid =
      spawn_link(fn ->
        case GuessTheSong.Quiz.add_sources(guild_id, voice_channel_id, tracks_per_user) do
          {:ok, sources} ->
            case GuessTheSong.Voice.Supervisor.start_session(guild_id, voice_channel_id) do
              {:ok, _pid} ->
                Nostrum.Api.Interaction.edit_response(interaction, %{
                  type: 7,
                  embeds: [GuessTheSong.Quiz.Embeds.starting(sources)]
                })

                GuessTheSong.Quiz.run_quiz(
                  guild_id,
                  text_channel_id,
                  rounds,
                  period
                )

              {:error, :already_active} ->
                Nostrum.Api.Interaction.edit_response(interaction, %{
                  type: 7,
                  embeds: [GuessTheSong.Quiz.Embeds.error("Bot is already in a voice channel")]
                })

                {:stop, :already_active}
            end

          {:error, :no_sources} ->
            IO.puts("No users with linked accounts in voice channel")

            Nostrum.Api.Interaction.edit_response(interaction, %{
              type: 7,
              embeds: [
                GuessTheSong.Quiz.Embeds.error("No users with linked accounts in voice channel")
              ]
            })

            {:stop, :no_sources}
        end
      end)

    {:ok,
     %{
       info: %{
         guild_id: guild_id,
         text_channel_id: text_channel_id,
         voice_channel_id: voice_channel_id,
         quiz_pid: pid,
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

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply, state.info, state}
  end

  @impl true
  def handle_call({:get_source, discord_id}, _from, state) do
    {:reply, state.sources[discord_id], state}
  end

  @impl true
  def handle_call(:get_random_track, _from, state) do
    {discord_id, source} = state.sources |> Map.to_list() |> Enum.random()
    track = Enum.random(source.choices)

    new_state = update_in(state, [:sources, discord_id, :choices], &(&1 |> MapSet.delete(track)))
    {:reply, {discord_id, source.lastfm, track}, new_state}
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
      new_round = %{
        track: track,
        number: state.round.number + 1,
        running: true,
        scores: %{}
      }

      {:noreply, put_in(state, [:round], new_round)}
    end
  end

  def handle_cast({:end_round}, state) do
    if state.round.running do
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
            state.info.guild_id,
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
  def handle_cast({:process_message, msg}, state) do
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

  @impl true
  def terminate(_reason, state) do
    IO.puts("Terminating GameServer for guild_id: #{state.info.guild_id}")

    if map_size(state.scores) > 0 do
      Nostrum.Api.Message.create(state.info.text_channel_id,
        embed: GuessTheSong.Quiz.Embeds.game_end(state.info.guild_id, state.scores)
      )
    end

    GuessTheSong.Voice.Supervisor.stop_session(state.info.guild_id)
  end
end
