defmodule GuessTheSong.DB.Repo do
  use Ecto.Repo,
    otp_app: :guess_the_song,
    adapter: Ecto.Adapters.SQLite3
end
