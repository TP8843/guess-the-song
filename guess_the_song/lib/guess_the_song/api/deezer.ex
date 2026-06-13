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
    defstruct [:id, :title, :artists, :url, :preview]

    @type t :: %__MODULE__{
      id: String.t(),
      title: String.t(),
      artists: [Artist.t()],
      url: String.t(),
      preview: String.t()
    }

    def parseJSON(json) do
      track = %__MODULE__{
        id: json["id"],
        title: json["title"],
        url: json["link"],
        preview: json["preview"]
      }

      # Parse the full list of artists from json
      artists = json["contributors"] |> Enum.map(fn artist -> Artist.parseJSON(artist, json["artist"]["id"]) end)
      %{track | artists: artists}
    end
  end

  @doc "Finds a match for the given query using the Deezer API"
  @spec find_match(GuessTheSong.Api.Lastfm.Track.t()) :: {:ok, map()} | {:error, any()}
  def find_match(lastfm_track) do
    query = "#{lastfm_track.title} #{lastfm_track.artist}"
    query = URI.encode(query)

    with  {:ok, response} <- search_fuzzy(query),
          %{body: body} <- response,
          {:ok, decoded} <- Jason.decode(body),
          %{"data" => tracks} <- decoded,
          [head | _] <- tracks,
          {:ok, response} <- fetch_track(head["id"]),
          %{body: body} <- response,
          {:ok, decoded} <- Jason.decode(body),
          track <- Track.parseJSON(decoded)
    do
      {:ok, track}
    else
      {:error, error} -> {:error, error}
      [] -> {:error, :not_found}
      %{} -> {:error, :invalid_response}
    end
  end

  @spec search_fuzzy(String.t(), pos_integer()) :: HTTPoison.Response.t()
  defp search_fuzzy(query, limit \\ 1) do
    query = URI.encode(query)
    url = "https://api.deezer.com/search?q=#{query}&limit=#{limit}"
    HTTPoison.get(url)
  end

  @spec search_exact(String.t(), String.t(), pos_integer()) :: HTTPoison.Response.t()
  defp search_exact(title, artist, limit \\ 1) do
    title = URI.encode(title)
    artist = URI.encode(artist)
    search = URI.encode("artist:\"#{artist}\",title:\"#{title}\"")
    url = "https://api.deezer.com/search?q=#{search}&limit=#{limit}"
    HTTPoison.get(url)
  end

  @spec fetch_track(String.t()) :: HTTPoison.Response.t()
  defp fetch_track(id) do
    url = "https://api.deezer.com/track/#{id}"
    HTTPoison.get(url)
  end
end
