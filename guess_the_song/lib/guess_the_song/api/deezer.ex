defmodule GuessTheSong.Api.Deezer do
  defmodule Artist do
    defstruct [:id, :name, :url, :role]

    @type t :: %__MODULE__{
      id: String.t(),
      name: String.t(),
      url: String.t(),
      role: String.t()
    }

    def parseJSON(json) do
      %__MODULE__{
        id: json["id"],
        name: json["name"],
        url: json["url"],
        role: json["role"]
      }
    end
  end

  defmodule Track do
    defstruct [:id, :title, :artists, :url]

    @type t :: %__MODULE__{
      id: String.t(),
      title: String.t(),
      artists: [Artist.t()],
      url: String.t()
    }
  end

  @doc "Finds a match for the given query using the Deezer API"
  @spec find_match(GuessTheSong.Api.Lastfm.Track.t()) :: {:ok, map()} | {:error, any()}
  def find_match(lastfm_track) do
    query = "#{lastfm_track.title} #{lastfm_track.artist}"
    query = URI.encode(query)
    case search_fuzzy(query) do
      {:ok, response} ->
        body = response.body |> Jason.decode!()
        case body["data"] |> Enum.count() do
          0 -> {:error, :not_found}
          _ -> {:ok, body |> Map.get("data") |> List.first()}
        end
      {:error, error} -> {:error, error}
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
end
