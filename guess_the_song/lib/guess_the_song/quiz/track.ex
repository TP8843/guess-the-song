defmodule GuessTheSong.Quiz.Track do
  defmodule GuessElement do
    defstruct [:string, :normalized_string, :type, :guessed, :guessed_by, :value]

    @type t :: %__MODULE__{
            string: String.t(),
            normalized_string: String.t(),
            type: String.t(),
            guessed: boolean(),
            guessed_by: integer() | nil,
            value: integer()
          }

    @spec create(String.t(), String.t(), integer()) :: t
    def create(string, type, value) do
      %__MODULE__{
        string: string,
        normalized_string: normalize_text(string),
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

      GuessTheSong.Helpers.Levenshtein.levenshtein_ratio(
        normalized_guess,
        guess_element.normalized_string
      ) >= 0.8
    end

    @spec normalize_text(String.t()) :: String.t()
    defp normalize_text(text) do
      text
      |> String.trim()
      |> String.normalize(:nfd)
      |> String.replace(~r/\s+/, " ")
      |> String.downcase()
      |> String.replace(~r/&/, "and")
      |> String.replace(~r/[\p{P}\p{S}]/, "")
      |> String.replace(~r/\([^)]*\)/, "")
      |> String.replace(~r/\\[.*]/, "")
      |> String.replace(~r/-.*/, "")
      |> String.replace(~r/feat.*/, "")
      |> String.replace(~r/part.*/, "")
      |> String.replace(~r/pt.*/, "")
      |> String.replace(~r/^the/, "")
    end
  end

  defstruct [:source, :guess_elements, :correct_guesses, :lastfm, :deezer]

  @type t :: %__MODULE__{
          source: integer(),
          guess_elements: [GuessElement.t()],
          correct_guesses: integer(),
          lastfm: Api.Lastfm.Track.t(),
          deezer: Api.Deezer.Track.t()
        }

  alias GuessTheSong.Api

  @spec create(Api.Lastfm.User.t(), Api.Lastfm.Track.t(), Api.Deezer.Track.t()) :: t
  def create(source, lastfm, deezer) do
    guess_elements =
      [GuessElement.create(deezer.title, "Title", 2)] ++
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
