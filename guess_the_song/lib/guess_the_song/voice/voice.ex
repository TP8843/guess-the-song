defmodule GuessTheSong.Voice do
  @moduledoc """
    Helper functions for voice channel operations.
  """

  @doc """
  Finds the voice channel for a given guild and user in Nostrum.
  """
  def find_voice_channel(guild_id, user_id) do
    case Nostrum.Cache.GuildCache.get(guild_id) do
      {:ok, guild} ->
        case Enum.find(guild.voice_states, fn
          vs ->
            vs.user_id == user_id
        end) do
          %{channel_id: channel_id} -> {:ok, channel_id}
          nil -> {:error, :not_in_voice_channel}
        end
      {:error, :not_found} -> {:error, :guild_not_found}
    end
  end
end
