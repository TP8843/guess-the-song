defmodule GuessTheSong.Api.Lastfm do
  defmodule Track do
    defstruct [
      :id,
      :title,
      :artist,
      :image_url,
      :url
    ]

    @type t :: %__MODULE__{
      id: String.t(),
      title: String.t(),
      artist: String.t(),
      image_url: String.t(),
      url: String.t()
    }

    def parseJSON(track) do
      %Track{
        id: Map.get(track, "id"),
        title: Map.get(track, "name"),
        artist: Map.get(track, "artist", %{}) |> Map.get("name"),
        image_url: Map.get(track, "image", []) |> List.last() |> Map.get("#text"),
        url: Map.get(track, "url")
      }
    end
  end

  @doc "Fetches the top tracks for a given user, limit, and period"
  @spec fetch_top_tracks(String.t(), integer(), :week | :month | :quarter_year | :half_year | :year | :overall) :: {:ok, [Track.t()]} | {:error, any()}
  def fetch_top_tracks(user, limit, period) do
    user = URI.encode(user)
    period = timeframe(period) |> URI.encode()
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    url = "https://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&user=#{user}&limit=#{limit}&period=#{period}&api_key=#{token}&format=json"
    IO.puts(url)
    case HTTPoison.get(url) do
      {:ok, response} ->
        tracks = Map.get(response, :body) |>
          Jason.decode!() |>
          Map.get("toptracks", []) |>
          Map.get("track", []) |>
          Enum.map(fn track -> Track.parseJSON(track) end)
        {:ok, tracks}

      {:error, reason} ->
        IO.inspect(reason)
        {:error, reason}
    end
  end

  @doc "Fetches the top tracks for a given user, limit, and period"
  @spec fetch_random_top_track(String.t(), integer(), :week | :month | :quarter_year | :half_year | :year | :overall) :: {:ok, Track.t()} | {:error, any()}
  def fetch_random_top_track(user, limit, period) do
    user = URI.encode(user)
    period = timeframe(period) |> URI.encode()
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    random_number = :rand.uniform(limit)
    url = "https://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&user=#{user}&limit=1&page=#{random_number}&period=#{period}&api_key=#{token}&format=json"
    IO.puts(url)
    case HTTPoison.get(url) do
      {:ok, response} ->
        track = Map.get(response, :body) |>
          Jason.decode!() |>
          Map.get("toptracks", []) |>
          Map.get("track", []) |>
          Enum.map(fn track -> Track.parseJSON(track) end) |>
          List.first()
        {:ok, track}

      {:error, reason} ->
        IO.inspect(reason)
        {:error, reason}
    end
  end

  def get_top_track_count(user, period) do
    user = URI.encode(user)
    period = timeframe(period) |> URI.encode()
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    url = "https://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&user=#{user}&limit=1&period=#{period}&api_key=#{token}&format=json"

    case HTTPoison.get(url) do
      {:ok, response} ->
        IO.inspect(response.body)
        count = Map.get(response, :body) |>
          Jason.decode!() |>
          Map.get("toptracks", %{}) |>
          Map.get("@attr", %{}) |>
          Map.get("total", 0)
        {:ok, count}

      {:error, reason} ->
        IO.inspect(reason)
        {:error, reason}
    end
  end

  @spec timeframe(:week | :month | :quarter_year | :half_year | :year | :overall):: String.t()
  defp timeframe(period) do
    case period do
      :week -> "7day"
      :month -> "1month"
      :quarter_year -> "3month"
      :half_year -> "6month"
      :year -> "12month"
      :overall -> "overall"
    end
  end
end
