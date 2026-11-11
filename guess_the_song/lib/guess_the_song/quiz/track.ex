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

    # Minimum similarity between a guess (or part of one) and an answer
    @min_similarity 0.8
    # Answers shorter than this, like "Yes", "Air" or "U2", only match inside a
    # longer message when spelled exactly, since one typo is a big change to a
    # short word
    @min_length_for_typos 4

    @spec match?(t, String.t()) :: boolean()
    @doc """
    Checks if the guess matches the guess element. An answer can be the whole
    message or any run of words inside it, so one message like
    "wonderwall oasis" can match several guess elements.
    """
    def match?(guess_element, guess) do
      normalized_guess = normalize_text(guess)

      normalized_guess != "" and
        Enum.any?(guess_element.answers, fn answer ->
          similar?(normalized_guess, answer) or in_message?(normalized_guess, answer)
        end)
    end

    defp similar?(text, answer) do
      GuessTheSong.Helpers.Levenshtein.levenshtein_ratio(text, answer) >= @min_similarity
    end

    # Compares the answer with every run of words in the message of about the
    # same length. Runs one word shorter or longer catch guesses that join or
    # split a word, e.g. "wonder wall" or "bohemianrhapsody".
    defp in_message?(normalized_guess, answer) do
      words = String.split(normalized_guess, " ")
      answer_words = answer |> String.split(" ") |> length()

      if String.length(answer) < @min_length_for_typos do
        words
        |> Enum.chunk_every(answer_words, 1, :discard)
        |> Enum.any?(&(Enum.join(&1, " ") == answer))
      else
        max(answer_words - 1, 1)..(answer_words + 1)
        |> Enum.any?(fn size ->
          words
          |> Enum.chunk_every(size, 1, :discard)
          |> Enum.any?(&similar?(Enum.join(&1, " "), answer))
        end)
      end
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

    defdelegate strip_version_info(title), to: GuessTheSong.Helpers.Text
    defdelegate normalize_text(text), to: GuessTheSong.Helpers.Text, as: :normalize
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
