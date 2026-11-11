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
    defstruct [:id, :title, :artists, :url, :preview, :cover, :gain]

    # `gain` isn't documented by Deezer, but matches the track's loudness in
    # LUFS (e.g. -5 for loud EDM, -16 for quiet acoustic). See `Quiz.Track.volume/1`.
    @type t :: %__MODULE__{
            id: String.t(),
            title: String.t(),
            artists: [Artist.t()],
            url: String.t(),
            preview: String.t(),
            cover: String.t(),
            gain: number() | nil
          }

    def parseJSON(json) do
      track = %__MODULE__{
        id: json["id"],
        title: json["title"],
        url: json["link"],
        preview: json["preview"],
        cover: json["album"]["cover"],
        gain: json["gain"]
      }

      # Parse the full list of artists from json
      artists =
        json["contributors"]
        |> Enum.map(fn artist -> Artist.parseJSON(artist, json["artist"]["id"]) end)

      %{track | artists: artists}
    end
  end

  alias GuessTheSong.Helpers.Text

  # How many search results to score
  @candidates 10
  # Minimum title and artist similarity for a result to count as a match
  @min_similarity 0.8
  # Score subtracted from versions the Last.fm title doesn't ask for, so the
  # original wins when both are found
  @version_penalty 0.2
  # Weight of the full title (version info included) matching exactly, so
  # "Song" prefers "Song" over "Song (Radio Edit)"
  @full_title_bonus 0.1

  # Never the same song for a quiz, unless the Last.fm track says so
  @rejected_words ~w(karaoke instrumental tribute)
  @rejected_phrases ["originally performed", "in the style of", "made famous"]
  # Still the same song, but the original is preferred
  @penalized_words ~w(live remix acoustic cover demo slowed sped nightcore)

  @doc """
  Finds the Deezer track matching a Last.fm track. Tries a strict field
  search first, then a fuzzy one, and scores the results against the Last.fm
  title and artist. Returns `{:error, :not_found}` rather than a poor match.
  """
  @spec find_match(GuessTheSong.Api.Lastfm.Track.t()) :: {:ok, Track.t()} | {:error, any()}
  def find_match(lastfm_track) do
    with {:ok, best} <- best_candidate(lastfm_track),
         # Deezer returns errors as a 200 with an "error" body, so check it's a track
         {:ok, %{"contributors" => _} = track} <- fetch_track(best["id"]) do
      {:ok, Track.parseJSON(track)}
    else
      {:error, error} -> {:error, error}
      _ -> {:error, :invalid_response}
    end
  end

  defp best_candidate(%{title: title, artist: artist} = lastfm_track) do
    searches = [
      fn -> search_exact(title, artist, @candidates) end,
      fn -> search_fuzzy("#{title} #{artist}", @candidates) end
    ]

    # Only fall back to the fuzzy search when the strict one finds no match.
    # API errors are returned straight away.
    Enum.reduce_while(searches, {:error, :not_found}, fn search, not_found ->
      case search.() do
        {:ok, %{"data" => results}} when is_list(results) ->
          case pick_best(results, lastfm_track) do
            nil -> {:cont, not_found}
            best -> {:halt, {:ok, best}}
          end

        {:ok, _} ->
          {:halt, {:error, :invalid_response}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp pick_best(results, lastfm_track) do
    results
    |> Enum.filter(&playable?/1)
    |> Enum.flat_map(fn result ->
      case score(result, lastfm_track) do
        nil -> []
        # Rounded so near-equal scores are decided by popularity
        score -> [{{Float.round(score, 2), result["rank"] || 0}, result}]
      end
    end)
    |> Enum.max_by(fn {key, _} -> key end, fn -> nil end)
    |> case do
      nil -> nil
      {_, result} -> result
    end
  end

  defp playable?(result) do
    result["readable"] != false and result["preview"] not in [nil, ""]
  end

  # Scores a search result against the Last.fm track, or returns nil if it
  # isn't a match
  defp score(result, lastfm_track) do
    title = title_similarity(result, lastfm_track.title)
    artist = artist_similarity(get_in(result, ["artist", "name"]) || "", lastfm_track.artist)
    described = description(result)
    requested = Text.normalize("#{lastfm_track.title} #{lastfm_track.artist}")

    cond do
      title < @min_similarity or artist < @min_similarity ->
        nil

      Enum.any?(@rejected_words, &unrequested_word?(described, requested, &1)) or
          Enum.any?(@rejected_phrases, &unrequested_word?(described, requested, &1)) ->
        nil

      true ->
        penalties = Enum.count(@penalized_words, &unrequested_word?(described, requested, &1))
        full_title = Text.similarity(result["title"] || "", lastfm_track.title)

        (title + artist) / 2 + full_title * @full_title_bonus -
          penalties * @version_penalty
    end
  end

  # Compares both the full titles and the titles without version info, since
  # Last.fm and Deezer often disagree on suffixes like "(feat. X)"
  defp title_similarity(result, lastfm_title) do
    deezer_title = result["title"] || ""
    deezer_short = result["title_short"] || Text.strip_version_info(deezer_title)
    lastfm_short = Text.strip_version_info(lastfm_title)

    Enum.max([
      Text.similarity(deezer_title, lastfm_title),
      Text.similarity(deezer_short, lastfm_short),
      Text.similarity(Text.strip_version_info(deezer_title), lastfm_short)
    ])
  end

  # Deezer search results only name the main artist, while Last.fm may list
  # several ("A & B", "A feat. B"), so compare against each of them too
  defp artist_similarity(deezer_artist, lastfm_artist) do
    parts =
      lastfm_artist
      |> String.split(~r/\s*(?:,|&|\bx\b|\bvs\.?|\bfeat\.?|\bft\.|\bfeaturing\b|\band\b)\s*/iu)
      |> Enum.reject(&(&1 == ""))

    [lastfm_artist, Text.strip_version_info(lastfm_artist) | parts]
    |> Enum.map(&Text.similarity(deezer_artist, &1))
    |> Enum.max()
  end

  # Everything that might reveal a result's version
  defp description(result) do
    [result["title"], get_in(result, ["artist", "name"]), get_in(result, ["album", "title"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> Text.normalize()
  end

  defp unrequested_word?(described, requested, word) do
    contains_word?(described, word) and not contains_word?(requested, word)
  end

  defp contains_word?(text, word) do
    Regex.match?(~r/\b#{Regex.escape(word)}\b/u, text)
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

  defp search_fuzzy(query, limit) do
    request("/search", q: query, limit: limit)
  end

  # Deezer's advanced search, matching the artist and track fields separately
  defp search_exact(title, artist, limit) do
    request("/search",
      q: ~s(artist:"#{strip_quotes(artist)}" track:"#{strip_quotes(title)}"),
      limit: limit
    )
  end

  # Double quotes would end the advanced search field early
  defp strip_quotes(text), do: String.replace(text, "\"", " ")

  defp fetch_track(id) do
    request("/track/#{id}")
  end
end
