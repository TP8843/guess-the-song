defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  alias GuessTheSong.Quiz.Server
  alias GuessTheSong.Api

  @doc """
    Runs the quiz on the given server.
  """
  @spec run_quiz(pid(), String.t(), String.t(), integer()) :: :ok
  def run_quiz(server, guild_id, text_channel_id, rounds) do
    {:ok, count} = Api.Lastfm.get_top_track_count("tp8843", :overall)

    IO.puts("Top track count: #{count}")

    count = min(100, count)

    Server.add_source(guild_id, 315179109661671425, "tp8843", count)

    Enum.each(1..rounds, fn _ ->
      {discord_id, lastfm_id, index} = Server.get_random_track(guild_id)
      {:ok, track} = Api.Lastfm.fetch_top_track_from_index(lastfm_id, :overall, index)
      case GuessTheSong.Api.Deezer.find_match(track) do
        {:ok, track} ->
          GuessTheSong.Voice.Server.play_audio(
            guild_id,
            track.preview
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
