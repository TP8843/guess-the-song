defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  import Ecto.Query

  alias GuessTheSong.Quiz
  alias GuessTheSong.Api

  @doc """
    Loads a player's Last.fm user and up to `max` of their top tracks for the
    period, which the quiz picks from. Fetching the tracks up front means
    rounds don't need to call Last.fm.
  """
  @spec load_source(integer(), String.t(), pos_integer(), String.t()) ::
          {:ok, {integer(), Api.Lastfm.User.t(), [Api.Lastfm.Track.t()]}} | {:error, any()}
  def load_source(discord_id, lastfm_id, max, period) do
    with {:ok, lastfm} <- Api.Lastfm.fetch_user(lastfm_id),
         {:ok, [_ | _] = tracks} <- Api.Lastfm.fetch_top_tracks(lastfm_id, max, period) do
      IO.puts("Loaded #{length(tracks)} top tracks for #{lastfm_id}")
      {:ok, {discord_id, lastfm, tracks}}
    else
      # Nothing played in this period
      {:ok, []} -> {:error, :no_tracks}
      {:error, reason} -> {:error, reason}
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
    Finds the Deezer match for one of the user's top tracks.
  """
  @spec fetch_track(Api.Lastfm.User.t(), Api.Lastfm.Track.t()) ::
          {:ok, Quiz.Track.t()} | {:error, any()}
  def fetch_track(lastfm, lastfm_track) do
    with {:ok, deezer} <- Api.Deezer.find_match(lastfm_track) do
      {:ok, Quiz.Track.create(lastfm, lastfm_track, deezer)}
    end
  end
end
