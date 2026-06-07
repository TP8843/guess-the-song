defmodule GuessTheSong.Quiz.Server do
  use GenServer, restart: :transient

  def start_link({guild_id, text_channel_id, voice_channel_id, rounds}) do
    GenServer.start_link(__MODULE__, {guild_id, text_channel_id, voice_channel_id, rounds}, name: via(guild_id))
  end

  def get_state(guild_id), do: GenServer.call(via(guild_id), :get_state)
  def add_player(guild_id, player), do: GenServer.cast(via(guild_id), {:add_player, player})
  def stop(guild_id), do: GenServer.stop(via(guild_id))

  defp via(guild_id) do
    {:via, Registry, {GuessTheSong.Quiz.Registry, guild_id}}
  end

  @impl true
  def init({guild_id, text_channel_id, voice_channel_id, rounds}) do
    IO.puts("Starting QuizServer for guild_id: #{guild_id} and text_channel_id: #{text_channel_id} and voice_channel_id: #{voice_channel_id} and rounds: #{rounds}")

    case GuessTheSong.Voice.Supervisor.start_session(guild_id, voice_channel_id) do
      {:ok, _pid} ->
        server = self()
        pid = spawn_link(fn -> GuessTheSong.Quiz.run_quiz(server, guild_id, text_channel_id, rounds) end)
        {:ok, %{
          guild_id: guild_id,
          text_channel_id: text_channel_id,
          voice_channel_id: voice_channel_id,
          players: [],
          quiz_pid: pid
        }}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:add_player, player}, state) do
    {:noreply, update_in(state.players, &[player | &1])}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    IO.puts("Quiz crashed: #{IO.inspect(reason)}")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    IO.puts("Terminating GameServer for guild_id: #{state.guild_id}")
    GuessTheSong.Voice.Supervisor.stop_session(state.guild_id)
  end
end
