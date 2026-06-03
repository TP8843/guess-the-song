defmodule GuessTheSong.QuizServerSupervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def active?(guild_id) do
    case Registry.lookup(GuessTheSong.QuizServerRegistry, guild_id) do
      [] -> false
      [{_pid, _}] -> true
    end
  end

  def start_session(guild_id) do
    case active?(guild_id) do
      false -> DynamicSupervisor.start_child(__MODULE__, {GuessTheSong.QuizServer, guild_id})
      true -> {:error, :already_started}
    end
  end

  def stop_session(guild_id) do
    case active?(guild_id) do
      true -> GuessTheSong.QuizServer.stop(guild_id)
      false -> :ok
    end
  end
end
