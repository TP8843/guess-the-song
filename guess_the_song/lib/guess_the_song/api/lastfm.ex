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
        image_url: Map.get(track, "image", []) |> List.last(%{}) |> Map.get("#text"),
        url: Map.get(track, "url")
      }
    end
  end

  defmodule User do
    defstruct [
      :name,
      :url,
      :playcount,
      :image
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            url: String.t(),
            playcount: String.t(),
            image: String.t()
          }

    def parseJSON(user) do
      %User{
        name: Map.get(user, "name"),
        url: Map.get(user, "url"),
        playcount: Map.get(user, "playcount"),
        image: Map.get(user, "image", []) |> Enum.at(3, %{}) |> Map.get("#text")
      }
    end
  end

  defp client do
    Req.new(
      base_url: "https://ws.audioscrobbler.com/2.0/",
      params: [api_key: Application.get_env(:guess_the_song, :lastfm_key), format: "json"],
      # Retries timeouts, 429s and 5xx errors. Two retries (about 1s, then 2s)
      # keeps a failing API from holding up a round for long.
      max_retries: 2
    )
    # Extra options from config, e.g. a Req.Test plug in tests
    |> Req.merge(Application.get_env(:guess_the_song, :req_options, []))
  end

  # Makes a Last.fm API request, returning the decoded JSON body. Error
  # statuses (after retries) are returned as `{:error, {:http_status, status}}`.
  defp request(params) do
    case Req.get(client(), params: params) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  def fetch_user(user) do
    with {:ok, %{"user" => user}} <- request(method: "user.getinfo", user: user) do
      {:ok, User.parseJSON(user)}
    else
      # Handle user not found
      {:error, {:http_status, 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  @doc """
  Fetches the top tracks for a given user, limit, and period. Last.fm allows a
  limit of up to 1000 (higher returns a 400).
  """
  @spec fetch_top_tracks(
          String.t(),
          integer(),
          String.t()
        ) :: {:ok, [Track.t()]} | {:error, any()}
  def fetch_top_tracks(user, limit, period) do
    params = [method: "user.gettoptracks", user: user, limit: limit, period: period]

    with {:ok, %{"toptracks" => %{"track" => track}}} <- request(params) do
      {:ok, track |> List.wrap() |> Enum.map(&Track.parseJSON/1)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end
end
