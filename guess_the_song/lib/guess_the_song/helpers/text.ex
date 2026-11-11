defmodule GuessTheSong.Helpers.Text do
  @moduledoc "Text normalization shared by guess checking and track matching."

  alias GuessTheSong.Helpers.Levenshtein

  @doc """
  Normalizes text for comparison: removes accents, case, punctuation and a
  leading "the", and collapses whitespace.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(text) do
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

  @doc "Removes the parts of a title that describe the version rather than the song."
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

  @doc """
  How similar two strings are after normalizing, from 0.0 to 1.0. Strings
  that are empty after normalizing never match.
  """
  @spec similarity(String.t(), String.t()) :: float()
  def similarity(a, b) do
    case {normalize(a), normalize(b)} do
      {"", _} -> 0.0
      {_, ""} -> 0.0
      {a, b} -> Levenshtein.levenshtein_ratio(a, b)
    end
  end
end
