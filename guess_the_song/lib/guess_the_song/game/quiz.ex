defmodule GuessTheSong.Quiz do
  @moduledoc """
    Runs a music guessing quiz on the given server.
  """

  alias GuessTheSong.Voice

  @doc """
    Runs the quiz on the given server.
  """
  def run_quiz(server, guild_id, _text_channel_id, _voice_channel_id) do
    Voice.Server.play_audio(
      guild_id,
      "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
    )

    Process.sleep(30000)
    send(server, :stop)
  end
end
