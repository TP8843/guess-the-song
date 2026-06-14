defmodule GuessTheSong.Quiz.Supervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one, restart: :temporary)
  end

  @doc """
    Returns whether a quiz session is active for the given guild.
  """
  def active?(guild_id) do
    case Registry.lookup(GuessTheSong.Quiz.Registry, guild_id) do
      [] -> false
      [{_pid, _}] -> true
    end
  end

  @doc """
    Returns the PID of the quiz session for the given guild, if one exists.
  """
  def get_session(guild_id) do
    case Registry.lookup(GuessTheSong.Quiz.Registry, guild_id) do
      [] -> {:error, :not_found}
      [{pid, value}] -> {:ok, {pid, value}}
    end
  end

  @doc """
    Starts a new quiz session for the given guild.
  """
  def start_session(guild_id, text_channel_id, voice_channel_id, rounds) do
    case active?(guild_id) do
      false -> DynamicSupervisor.start_child(__MODULE__, {
        GuessTheSong.Quiz.Server,
        {guild_id, text_channel_id, voice_channel_id, rounds}
      })
      true -> {:error, :already_started}
    end
  end

  @doc """
    Stops the quiz session for the given guild, if one exists.
  """
  def stop_session(guild_id) do
    case active?(guild_id) do
      true -> GuessTheSong.Quiz.Server.stop(guild_id)
      false -> :ok
    end
  end
end
