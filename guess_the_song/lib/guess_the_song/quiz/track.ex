defmodule GuessTheSong.Quiz.Track do
  defmodule GuessElement do
    defstruct [:string, :answers, :type, :guessed, :guessed_by, :value]

    @type t :: %__MODULE__{
            string: String.t(),
            answers: [String.t()],
            type: String.t(),
            guessed: boolean(),
            guessed_by: integer() | nil,
            value: integer()
          }

    @doc """
    Creates a guess element. With `strip_version: true` (for song titles), the
    title without version info such as "(Remix)" or "- Remastered 2011" is
    accepted as well as the full title.
    """
    @spec create(String.t(), String.t(), integer(), keyword()) :: t
    def create(string, type, value, opts \\ []) do
      %__MODULE__{
        string: string,
        answers: answers(string, Keyword.get(opts, :strip_version, false)),
        type: type,
        guessed: false,
        guessed_by: nil,
        value: value
      }
    end

    @spec match?(t, String.t()) :: boolean()
    @doc "Checks if the guess matches the guess element."
    def match?(guess_element, guess) do
      normalized_guess = normalize_text(guess)

      normalized_guess != "" and
        Enum.any?(guess_element.answers, fn answer ->
          GuessTheSong.Helpers.Levenshtein.levenshtein_ratio(normalized_guess, answer) >= 0.8
        end)
    end

    defp answers(string, strip_version?) do
      variants = if strip_version?, do: [string, strip_version_info(string)], else: [string]

      variants
      |> Enum.map(&normalize_text/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> case do
        # Nothing left after normalizing (e.g. a title made of symbols)
        [] -> [string |> String.trim() |> String.downcase()]
        answers -> answers
      end
    end

    # Removes the parts of a title that describe the version rather than the song
    @spec strip_version_info(String.t()) :: String.t()
    def strip_version_info(title) do
      title
      # "(Remix)", "[Live]", "(feat. X)"
      |> String.replace(~r/[(\[][^)\]]*[)\]]/u, "")
      # "- Remastered 2011". Needs spaces around the dash, so "Jay-Z" is kept.
      |> String.replace(~r/\s+[-–—]\s.*$/u, "")
      # "feat. X" without brackets
      |> String.replace(~r/\s+(feat\.?|ft\.|featuring)\s.*$/iu, "")
      |> String.trim()
    end

    @spec normalize_text(String.t()) :: String.t()
    def normalize_text(text) do
      text
      |> String.normalize(:nfd)
      # Remove accents, which NFD splits off from their letters
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.replace("&", " and ")
      |> String.replace(~r/[\p{P}\p{S}]/u, "")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.replace(~r/^the /u, "")
    end
  end

  alias GuessTheSong.Api

  defstruct [:source, :guess_elements, :correct_guesses, :lastfm, :deezer]

  @type t :: %__MODULE__{
          source: Api.Lastfm.User.t(),
          guess_elements: [GuessElement.t()],
          correct_guesses: integer(),
          lastfm: Api.Lastfm.Track.t(),
          deezer: Api.Deezer.Track.t()
        }

  @spec create(Api.Lastfm.User.t(), Api.Lastfm.Track.t(), Api.Deezer.Track.t()) :: t
  def create(source, lastfm, deezer) do
    guess_elements =
      [GuessElement.create(deezer.title, "Title", 2, strip_version: true)] ++
        Enum.map(deezer.artists, fn c ->
          GuessElement.create(
            c.name,
            "#{if(c.role == :main, do: "Main", else: "Featured")} artist",
            if(c.role == :main, do: 2, else: 1)
          )
        end)

    %__MODULE__{
      source: source,
      lastfm: lastfm,
      deezer: deezer,
      guess_elements: guess_elements,
      correct_guesses: 0
    }
  end
end
