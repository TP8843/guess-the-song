defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  alias GuessTheSong.Voice
  alias GuessTheSong.Api

  @doc """
    Runs the quiz on the given server.
  """
  @spec run_quiz(pid(), String.t(), String.t(), integer()) :: :ok
  def run_quiz(server, guild_id, text_channel_id, rounds) do
    {:ok, count} = Api.Lastfm.get_top_track_count("tp8843", :overall)

    IO.puts("Top track count: #{count}")

    count = min(100, count)

    Enum.each(1..rounds, fn _ ->
      {:ok, random_number, track} = Api.Lastfm.fetch_random_top_track("tp8843", count, :overall)
      case GuessTheSong.Api.Deezer.find_match(track) do
        {:ok, track} ->
          Voice.Server.play_audio(
            guild_id,
            Map.get(track, "preview")
          )
          Process.sleep(30000)
          Nostrum.Api.Message.create(text_channel_id, content: "Time's up! The song was: #{Map.get(track, "title")} by #{Map.get(track, "artist") |> Map.get("name")}")

        {:error, error} ->
          IO.inspect(error)
          :ok
      end
    end)

    send(server, :stop)
  end
end
