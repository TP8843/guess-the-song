defmodule GuessTheSong.Voice.Supervisor do
  @moduledoc """
    Supervisor for voice session servers.
  """

  use DynamicSupervisor

  @doc """
    Starts the voice supervisor.
  """
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
    Returns whether a voice session is active for the given guild.
  """
  def active?(guild_id) do
    case Registry.lookup(GuessTheSong.Voice.Registry, guild_id) do
      [] -> false
      [{_pid, _}] -> true
    end
  end

  @doc """
    Returns the PID of the voice session for the given guild, if one exists.
  """
  def get_session(guild_id) do
    case Registry.lookup(GuessTheSong.Voice.Registry, guild_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, pid}
    end
  end

  @doc """
    Starts a voice session for the given guild and channel.
  """
  def start_session(guild_id, channel_id) do
    case active?(guild_id) do
      false ->
        DynamicSupervisor.start_child(
          __MODULE__,
          {GuessTheSong.Voice.Server, {guild_id, channel_id}}
        )

      true ->
        {:error, :already_active}
    end
  end

  @doc """
    Stops the voice session for the given guild.
  """
  def stop_session(guild_id) do
    case active?(guild_id) do
      true -> GuessTheSong.Voice.Server.leave(guild_id)
      false -> :ok
    end
  end
end
