defmodule GuessTheSong.Quiz.TrackTest do
  use ExUnit.Case, async: true

  alias GuessTheSong.Quiz.Track.GuessElement

  defp title(string), do: GuessElement.create(string, "Title", 2, strip_version: true)
  defp artist(string), do: GuessElement.create(string, "Main artist", 2)

  describe "strip_version_info/1" do
    test "removes brackets" do
      assert GuessElement.strip_version_info("Hello (Remix)") == "Hello"
      assert GuessElement.strip_version_info("Song [Live]") == "Song"
      assert GuessElement.strip_version_info("Gangnam Style (feat. PSY)") == "Gangnam Style"
    end

    test "removes everything after a spaced dash" do
      assert GuessElement.strip_version_info("Wonderwall - Remastered 2014") == "Wonderwall"
      assert GuessElement.strip_version_info("Song – Radio Edit") == "Song"
    end

    test "keeps unspaced hyphens" do
      assert GuessElement.strip_version_info("Re-Arranged") == "Re-Arranged"
    end

    test "removes unbracketed featured artists" do
      assert GuessElement.strip_version_info("Song feat. Someone") == "Song"
      assert GuessElement.strip_version_info("Song ft. Someone") == "Song"
    end
  end

  describe "normalize_text/1" do
    test "doesn't cut words that start like removed words" do
      assert GuessElement.normalize_text("September") == "september"
      assert GuessElement.normalize_text("Theory") == "theory"
      assert GuessElement.normalize_text("Apartment") == "apartment"
    end

    test "removes a leading \"the\"" do
      assert GuessElement.normalize_text("The Beatles") == "beatles"
    end

    test "removes accents, punctuation and extra spaces" do
      assert GuessElement.normalize_text("  Café   del Mar! ") == "cafe del mar"
      assert GuessElement.normalize_text("Don't Stop") == "dont stop"
      assert GuessElement.normalize_text("Simon & Garfunkel") == "simon and garfunkel"
    end
  end

  describe "match?/2" do
    test "accepts titles with or without version info" do
      element = title("Wonderwall - Remastered 2014")
      assert GuessElement.match?(element, "wonderwall")
      assert GuessElement.match?(element, "Wonderwall - Remastered 2014")
    end

    test "accepts the full title when brackets are part of it" do
      element = title("(I Can't Get No) Satisfaction")
      assert GuessElement.match?(element, "satisfaction")
      assert GuessElement.match?(element, "I can't get no satisfaction")
    end

    test "allows small typos" do
      assert GuessElement.match?(title("Bohemian Rhapsody"), "bohemian rapsody")
      refute GuessElement.match?(title("Bohemian Rhapsody"), "bohemian")
    end

    test "doesn't strip version info from artists" do
      assert GuessElement.match?(artist("Jay-Z"), "jay z")
      refute GuessElement.match?(artist("Someone - Else"), "someone")
    end

    test "never matches an empty guess" do
      refute GuessElement.match?(title("(Untitled)"), "!!!")
      refute GuessElement.match?(title("Song"), "")
    end
  end
end
