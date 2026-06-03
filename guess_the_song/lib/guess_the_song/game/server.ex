defmodule GuessTheSong.QuizServer do
  use GenServer, restart: :transient

  def start_link(guild_id) do
    GenServer.start_link(__MODULE__, guild_id, name: via(guild_id))
  end

  def get_state(guild_id), do: GenServer.call(via(guild_id), :get_state)
  def add_player(guild_id, player), do: GenServer.cast(via(guild_id), {:add_player, player})
  def stop(guild_id), do: GenServer.stop(via(guild_id))

  defp via(guild_id) do
    {:via, Registry, {GuessTheSong.QuizServerRegistry, guild_id}}
  end

  @impl true
  def init(guild_id) do
    IO.puts("Starting QuizServer for guild_id: #{guild_id}")

    server = self()
    pid = spawn_link(fn -> GuessTheSong.Quiz.run_quiz(server) end)

    {:ok, %{guild_id: guild_id, players: [], quiz_pid: pid}}
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
  def terminate(_reason, state) do
    IO.puts("Terminating GameServer for guild_id: #{state.guild_id}")
  end
end
