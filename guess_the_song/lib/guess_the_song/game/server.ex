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

  def get_source(guild_id, discord_id), do: GenServer.call(via(guild_id), {:get_source, discord_id})

  @spec get_random_track(guild_id :: integer) :: {discord_id :: integer, lastfm_id :: String.t(), track :: integer}
  def get_random_track(guild_id), do: GenServer.call(via(guild_id), :get_random_track)

  @spec add_source(guild_id :: integer, discord_id :: integer, lastfm_id :: String.t(), count :: integer) :: :ok
  def add_source(guild_id, discord_id, lastfm_id, count), do: GenServer.cast(via(guild_id), {:add_source, {discord_id, lastfm_id, count}})

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
             track: nil,
           },
           sources: %{},
           scores: %{},
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
        running: true,
      }

      {:noreply, put_in(state, [:round], new_round)}
    end
  end

  def handle_cast({:end_round}, state) do
    if state.round.running do
      Nostrum.Api.Message.create(state.info.text_channel_id, content: "Time's up! The song was: #{state.round.track.title}")
      send(state.info.quiz_pid, {:round_ended})
      {:noreply, put_in(state, [:round, :running], false)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:process_message, msg}, state) do
    IO.puts("Processing message: #{msg.content} from user: #{msg.author.username}")

    {:noreply, state}
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

    Nostrum.Api.Message.create(state.info.text_channel_id, content: "Quiz ended! Scores are so coming soon :D")

    GuessTheSong.Voice.Supervisor.stop_session(state.info.guild_id)
  end
end
