defmodule GuessTheSong.Api.Deezer do
  defmodule Artist do
    defstruct [:id, :name, :url, :role]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            url: String.t(),
            role: :main | :feat
          }

    def parseJSON(json, main_artist \\ 0) do
      %__MODULE__{
        id: json["id"],
        name: json["name"],
        url: json["link"],
        role: if(main_artist == json["id"], do: :main, else: :feat)
      }
    end
  end

  defmodule Track do
    defstruct [:id, :title, :artists, :url, :preview, :cover]

    @type t :: %__MODULE__{
            id: String.t(),
            title: String.t(),
            artists: [Artist.t()],
            url: String.t(),
            preview: String.t(),
            cover: String.t()
          }

    def parseJSON(json) do
      track = %__MODULE__{
        id: json["id"],
        title: json["title"],
        url: json["link"],
        preview: json["preview"],
        cover: json["album"]["cover"]
      }

      # Parse the full list of artists from json
      artists =
        json["contributors"]
        |> Enum.map(fn artist -> Artist.parseJSON(artist, json["artist"]["id"]) end)

      %{track | artists: artists}
    end
  end

  @doc "Finds a match for the given query using the Deezer API"
  @spec find_match(GuessTheSong.Api.Lastfm.Track.t()) :: {:ok, Track.t()} | {:error, any()}
  def find_match(lastfm_track) do
    query = "#{lastfm_track.title} #{lastfm_track.artist}"

    with {:ok, %{"data" => [head | _]}} <- search_fuzzy(query),
         # Deezer returns errors as a 200 with an "error" body, so check it's a track
         {:ok, %{"contributors" => _} = track} <- fetch_track(head["id"]) do
      {:ok, Track.parseJSON(track)}
    else
      {:ok, %{"data" => []}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
      _ -> {:error, :invalid_response}
    end
  end

  defp client do
    # Retries timeouts, 429s and 5xx errors. Two retries (about 1s, then 2s)
    # keeps a failing API from holding up a round for long.
    Req.new(base_url: "https://api.deezer.com", max_retries: 2)
    # Extra options from config, e.g. a Req.Test plug in tests
    |> Req.merge(Application.get_env(:guess_the_song, :req_options, []))
  end

  # Makes a Deezer API request, returning the decoded JSON body. Error
  # statuses (after retries) are returned as `{:error, {:http_status, status}}`.
  @spec request(String.t(), keyword()) :: {:ok, term()} | {:error, any()}
  defp request(path, params \\ []) do
    case Req.get(client(), url: path, params: params) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp search_fuzzy(query, limit \\ 1) do
    request("/search", q: query, limit: limit)
  end

  defp search_exact(title, artist, limit \\ 1) do
    request("/search", q: "artist:\"#{artist}\",title:\"#{title}\"", limit: limit)
  end

  defp fetch_track(id) do
    request("/track/#{id}")
  end
end
