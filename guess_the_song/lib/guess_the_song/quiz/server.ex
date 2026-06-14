defmodule GuessTheSong.Quiz.Server do
  use GenServer, restart: :transient

  alias Nostrum.Api.Message

  def start_link({guild_id, text_channel_id, voice_channel_id, rounds}) do
    GenServer.start_link(
      __MODULE__,
      {guild_id, text_channel_id, voice_channel_id, rounds},
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
          lastfm_id :: String.t(),
          count :: integer
        ) :: :ok
  def add_source(guild_id, discord_id, lastfm_id, count),
    do: GenServer.cast(via(guild_id), {:add_source, {discord_id, lastfm_id, count}})

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
  def init({guild_id, text_channel_id, voice_channel_id, rounds}) do
    IO.puts(
      "Starting QuizServer for guild_id: #{guild_id} and text_channel_id: #{text_channel_id} and voice_channel_id: #{voice_channel_id} and rounds: #{rounds}"
    )

    case GuessTheSong.Voice.Supervisor.start_session(guild_id, voice_channel_id) do
      {:ok, _pid} ->
        server = self()

        # Ensure that if the quiz process exits, the server is stopped
        Process.flag(:trap_exit, true)

        pid =
          spawn_link(fn ->
            GuessTheSong.Quiz.run_quiz(server, guild_id, text_channel_id, rounds)
          end)

        {:ok,
         %{
           info: %{
             guild_id: guild_id,
             text_channel_id: text_channel_id,
             voice_channel_id: voice_channel_id,
             quiz_pid: pid,
             rounds: rounds
           },
           round: %{
             number: 0,
             running: false,
             track: nil
           },
           sources: %{},
           scores: %{}
         }}

      {:error, reason} ->
        {:stop, reason}
    end
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
    {:reply, {discord_id, source.lastfm_id, track}, new_state}
  end

  @impl true
  def handle_cast({:add_source, {discord_id, lastfm_id, count}}, state) do
    {:noreply,
     update_in(
       state.sources,
       &Map.put(&1, discord_id, %{lastfm_id: lastfm_id, choices: MapSet.new(1..count)})
     )}
  end

  @impl true
  def handle_cast({:start_round, track}, state) do
    if state.round.running do
      {:noreply, state}
    else
      new_round = %{
        track: track,
        number: state.round.number + 1,
        running: true
      }

      {:noreply, put_in(state, [:round], new_round)}
    end
  end

  def handle_cast({:end_round}, state) do
    if state.round.running do
      Nostrum.Api.Message.create(state.info.text_channel_id,
        content: "Time's up! The song was: #{state.round.track.deezer.title}, by #{state.round.track.deezer.artists |> Enum.reduce("", fn contributor, acc -> acc <> contributor.name <> ", " end) |> String.trim_trailing()}"
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

    new_state = state

    new_state = Enum.reduce(state.round.track.guess_elements, new_state, fn guess_element, acc ->
      if not guess_element.guessed and GuessElement.match?(guess_element, msg.content) do
        Nostrum.Api.Message.create(state.info.text_channel_id,
          content: "Correct! #{guess_element.type} is: #{guess_element.string}",
          message_reference: %{message_id: msg.id}
        )

        acc = update_in(acc, [:round, :track], fn track ->
          %{track | guess_elements: Enum.map(track.guess_elements, fn element ->
            if element == guess_element do
              %{element | guessed: true}
            else
              element
            end
          end)}
        end)
        acc = update_in(acc, [:scores], &Map.update(&1, msg.author.id, guess_element.value, fn value -> value + guess_element.value end))
        acc
      else
        acc
      end
    end)

    IO.inspect(new_state.scores)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    IO.puts("Quiz ended normally")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    if pid == state.info.quiz_pid do
      IO.puts("Quiz crashed in server #{state.info.guild_id}: #{IO.inspect(reason)}")
      Message.create(state.info.text_channel_id, "Oops. Something went wrong running the quiz :(")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    IO.puts("Terminating GameServer for guild_id: #{state.info.guild_id}")
    IO.inspect(state.scores)

    Nostrum.Api.Message.create(state.info.text_channel_id,
      content: "Quiz ended! #{Enum.reduce(state.scores, "", fn {user_id, score}, acc ->
        {:ok, user} = Nostrum.Cache.MemberCache.get(state.info.guild_id, user_id)
        acc <> "#{user.nick}: #{score}\n"
      end)}"
    )

    GuessTheSong.Voice.Supervisor.stop_session(state.info.guild_id)
  end
end
