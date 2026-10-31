defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  import Ecto.Query

  alias GuessTheSong.Quiz
  alias GuessTheSong.Quiz.Server
  alias GuessTheSong.Api

  # How many tracks to try before giving up on finding a Deezer match for a round
  @max_track_attempts 5

  @doc """
    Adds a source to the quiz for the given guild.
  """
  @spec add_source(String.t(), integer(), String.t(), integer()) :: :ok | {:error, any()}
  def add_source(guild_id, discord_id, lastfm_id, max) do
    with {:ok, lastfm} <- Api.Lastfm.fetch_user(lastfm_id),
         {:ok, count} <- Api.Lastfm.get_top_track_count(lastfm_id, "overall"),
         IO.puts("Top track count: #{count}"),
         # Skip empty libraries, since 1..0 counts down to [1, 0] rather than being empty
         count when count > 0 <- min(max, count) do
      Server.add_source(guild_id, discord_id, lastfm, count)
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

  @spec run_round(String.t(), String.t(), non_neg_integer()) ::
          {:ok, Quiz.Track.t()} | {:error, any()}
  def run_round(guild_id, period, attempts \\ 0)

  def run_round(_guild_id, _period, attempts) when attempts >= @max_track_attempts,
    do: {:error, :no_match}

  def run_round(guild_id, period, attempts) do
    case Server.get_random_track(guild_id) do
      {:ok, {_discord_id, lastfm, index}} ->
        with {:ok, lastfm_track} <-
               Api.Lastfm.fetch_top_track_from_index(lastfm.name, period, index),
             {:ok, deezer} <- GuessTheSong.Api.Deezer.find_match(lastfm_track) do
          {:ok, Quiz.Track.create(lastfm, lastfm_track, deezer)}
        else
          # Track missing on Last.fm or Deezer, so try a different one
          {:error, :not_found} ->
            run_round(guild_id, period, attempts + 1)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :no_tracks} ->
        {:error, :no_tracks}
    end
  end

  @doc """
    Runs the quiz on the given server.
  """
  @spec run_quiz(String.t(), String.t(), integer(), String.t()) :: :ok
  def run_quiz(guild_id, text_channel_id, rounds, period) do
    Enum.reduce_while(1..rounds, :ok, fn _, _ ->
      case run_round(guild_id, period) do
        {:ok, track} ->
          :timer.sleep(1000)

          GuessTheSong.Voice.Server.play_audio(
            guild_id,
            track.deezer.preview,
            :url,
            volume: 0.4
          )

          Server.start_round(guild_id, track)

          receive do
            {:round_ended} -> :ok
          end

          GuessTheSong.Voice.Server.stop_audio(guild_id)
          {:cont, :ok}

        # Every source has run out of tracks, so end the quiz early
        {:error, :no_tracks} ->
          {:halt, :ok}

        {:error, error} ->
          IO.inspect(error)
          {:cont, :ok}
      end
    end)
  end
end
