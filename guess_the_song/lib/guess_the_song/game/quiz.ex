defmodule GuessTheSong.Quiz do
  def run_quiz(server) do
    Process.sleep(10000)
    send(server, :stop)
  end
end
