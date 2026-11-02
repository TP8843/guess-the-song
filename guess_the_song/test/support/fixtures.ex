defmodule GuessTheSong.Fixtures do
  @moduledoc "Helpers for serving saved API responses from `test/fixtures`."

  @dir Path.expand("../fixtures", __DIR__)

  @doc "Reads and decodes a saved JSON response, e.g. `load(\"deezer/track\")`."
  def load(name) do
    @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
  end

  @doc "Responds to a Req.Test request with a saved JSON response."
  def respond(conn, name, status \\ 200) do
    conn
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(load(name))
  end
end
