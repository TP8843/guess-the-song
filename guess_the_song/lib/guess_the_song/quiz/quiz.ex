defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  import Ecto.Query

  alias GuessTheSong.Quiz
  alias GuessTheSong.Api

  @doc """
    Loads a player's Last.fm user and how many of their top tracks to pick from.
  """
  @spec load_source(integer(), String.t(), integer()) ::
          {:ok, {integer(), Api.Lastfm.User.t(), pos_integer()}} | {:error, any()}
  def load_source(discord_id, lastfm_id, max) do
    with {:ok, lastfm} <- Api.Lastfm.fetch_user(lastfm_id),
         {:ok, count} <- Api.Lastfm.get_top_track_count(lastfm_id, "overall"),
         IO.puts("Top track count: #{count}"),
         # Skip empty libraries, since 1..0 counts down to [1, 0] rather than being empty
         count when count > 0 <- min(max, count) do
      {:ok, {discord_id, lastfm, count}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_tracks}
    end
  end

  @doc """
    Returns all users in a voice channel who have a linked Last.fm account.
    Each entry is a `GuessTheSong.DB.User` struct.
  """
  @spec eligible_users(String.t(), integer()) :: [GuessTheSong.DB.User.t()]
  def eligible_users(guild_id, channel_id) do
    {:ok, guild} = Nostrum.Cache.GuildCache.get(guild_id)

    user_ids =
      guild.voice_states
      |> Enum.filter(fn vs -> vs.channel_id == channel_id end)
      |> Enum.map(fn vs -> vs.user_id end)

    GuessTheSong.DB.Repo.all(from(u in GuessTheSong.DB.User, where: u.discord_id in ^user_ids))
  end

  @doc """
    Fetches the user's top track at the given index and finds its Deezer match.
  """
  @spec fetch_track(Api.Lastfm.User.t(), String.t(), integer()) ::
          {:ok, Quiz.Track.t()} | {:error, any()}
  def fetch_track(lastfm, period, index) do
    with {:ok, lastfm_track} <- Api.Lastfm.fetch_top_track_from_index(lastfm.name, period, index),
         {:ok, deezer} <- Api.Deezer.find_match(lastfm_track) do
      {:ok, Quiz.Track.create(lastfm, lastfm_track, deezer)}
    end
  end
end
