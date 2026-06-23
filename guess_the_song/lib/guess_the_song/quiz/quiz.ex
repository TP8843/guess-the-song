defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  import Ecto.Query

  alias GuessTheSong.Quiz
  alias GuessTheSong.Quiz.Server
  alias GuessTheSong.Api

  @doc """
    Adds a source to the quiz for the given guild.
  """
  @spec add_source(String.t(), integer(), String.t(), integer()) :: :ok
  def add_source(guild_id, discord_id, lastfm_id, max) do
    {:ok, lastfm} = Api.Lastfm.fetch_user(lastfm_id)

    {:ok, count} = Api.Lastfm.get_top_track_count(lastfm_id, :overall)

    IO.puts("Top track count: #{count}")
    count = min(max, count)

    Server.add_source(guild_id, discord_id, lastfm, count)
  end

  @doc """
    Adds all sources from a voice channel to the quiz
  """
  @spec add_sources(String.t(), integer(), integer()) :: :ok
  def add_sources(guild_id, channel_id, max \\ 100) do
    {:ok, guild} = Nostrum.Cache.GuildCache.get(guild_id)

    user_ids =
      guild.voice_states
      |> Enum.filter(fn vs -> vs.channel_id == channel_id end)
      |> Enum.map(fn vs -> vs.user_id end)

    case GuessTheSong.DB.Repo.all(from(u in GuessTheSong.DB.User, where: u.discord_id in ^user_ids)) do
      [] -> {:error, :no_sources}
      sources ->
        Enum.each(sources, fn source ->
          add_source(guild_id, source.discord_id, source.lastfm_username, max)
        end)
        {:ok, sources}
    end
  end

  def run_round(guild_id) do
    {discord_id, lastfm, index} = Server.get_random_track(guild_id)
    {:ok, lastfm_track} = Api.Lastfm.fetch_top_track_from_index(lastfm.name, :overall, index)

    case GuessTheSong.Api.Deezer.find_match(lastfm_track) do
      {:ok, deezer} ->
        track = Quiz.Track.create(lastfm, lastfm_track, deezer)
        {:ok, track}

      {:error, :not_found} ->
        run_round(guild_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
    Runs the quiz on the given server.
  """
  @spec run_quiz(String.t(), String.t(), integer()) :: :ok
  def run_quiz(guild_id, text_channel_id, rounds) do
    Enum.each(1..rounds, fn _ ->
      case run_round(guild_id) do
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

        {:error, error} ->
          IO.inspect(error)
          :ok
      end
    end)
  end
end
