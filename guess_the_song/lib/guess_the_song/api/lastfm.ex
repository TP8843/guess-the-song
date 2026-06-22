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

  defmodule User do
    defstruct [
      :name,
      :url,
      :image
    ]

    @type t :: %__MODULE__{
      name: String.t(),
      url: String.t(),
      image: String.t()
    }

    def parseJSON(user) do
      %User{
        name: Map.get(user, "name"),
        url: Map.get(user, "url"),
        image: Enum.at(Map.get(user, "image"), 3) |> Map.get("#text")
      }
    end
  end

  def fetch_user(user) do
    user = URI.encode(user)
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    url = "https://ws.audioscrobbler.com/2.0/?method=user.getinfo&user=#{user}&api_key=#{token}&format=json"

    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(url),
         {:ok, body} <- Jason.decode(body),
         %{"user" => user} <- body,
         user <- User.parseJSON(user) do
      {:ok, user}
    else
      # Handle user not found
      {:ok, %{status_code: 404}} -> {:error, :not_found}
      # Handle other errors
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetches the top tracks for a given user, limit, and period"
  @spec fetch_top_tracks(String.t(), integer(), :week | :month | :quarter_year | :half_year | :year | :overall) :: {:ok, [Track.t()]} | {:error, any()}
  def fetch_top_tracks(user, limit, period) do
    user = URI.encode(user)
    period = timeframe(period) |> URI.encode()
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    url = "https://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&user=#{user}&limit=#{limit}&period=#{period}&api_key=#{token}&format=json"

    with {:ok, response} <- HTTPoison.get(url),
         {:ok, body} <- Jason.decode(response.body),
         %{"toptracks" => toptracks} <- body,
         %{"track" => track} <- toptracks,
         tracks <- Enum.map(track, fn t -> Track.parseJSON(t) end) do
      {:ok, tracks}
    else
      {:error, reason} -> {:error, reason}
      %{} -> {:error, :invalid_response}
    end
  end

  @doc "Fetches a random top track for a given user, limit, and period"
  @spec fetch_random_top_track(String.t(), integer(), :week | :month | :quarter_year | :half_year | :year | :overall) :: {:ok, Track.t()} | {:error, any()}
  def fetch_random_top_track(user, limit, period) do
    random_number = :rand.uniform(limit)
    fetch_top_track_from_index(user, period, random_number)
  end

  @doc "Fetches top track for a given user, period, and index"
  @spec fetch_top_track_from_index(String.t(), :week | :month | :quarter_year | :half_year | :year | :overall, integer()) :: {:ok, Track.t()} | {:error, any()}
  def fetch_top_track_from_index(user, period, index) do
    user = URI.encode(user)
    period = timeframe(period) |> URI.encode()
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    url = "https://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&user=#{user}&limit=1&page=#{index}&period=#{period}&api_key=#{token}&format=json"

    with {:ok, response} <- HTTPoison.get(url),
         {:ok, body} <- Jason.decode(response.body),
         %{"toptracks" => toptracks} <- body,
         %{"track" => track} <- toptracks,
         tracks <- Enum.map(track, fn t -> Track.parseJSON(t) end),
         [track | _] <- tracks do
      {:ok, track}
    else
      {:error, reason} -> {:error, reason}
      %{} -> {:error, :invalid_response}
    end
  end

  def get_top_track_count(user, period) do
    user = URI.encode(user)
    period = timeframe(period) |> URI.encode()
    token = Application.get_env(:guess_the_song, :lastfm_key) |> URI.encode()
    url = "https://ws.audioscrobbler.com/2.0/?method=user.gettoptracks&user=#{user}&limit=1&period=#{period}&api_key=#{token}&format=json"

    with {:ok, response} <- HTTPoison.get(url),
         %{body: body} <- response,
         {:ok, decoded} <- Jason.decode(body),
         %{"toptracks" => %{"@attr" => %{"total" => total}}} <- decoded do
        {:ok, total}
    else
      {:error, reason} -> {:error, reason}
      %{} -> {:error, :invalid_response}
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
