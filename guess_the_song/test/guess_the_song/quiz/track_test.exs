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

  describe "match?/2 with longer messages" do
    test "finds the title and the artist in one message" do
      assert GuessElement.match?(title("Wonderwall"), "wonderwall oasis")
      assert GuessElement.match?(artist("Oasis"), "wonderwall oasis")
    end

    test "finds an answer inside a sentence" do
      assert GuessElement.match?(title("Wonderwall"), "is it wonderwall?")
      assert GuessElement.match?(title("Bohemian Rhapsody"), "surely this is bohemian rhapsody")
      assert GuessElement.match?(artist("The Killers"), "i think it's the killers")
    end

    test "finds titles without version info inside a sentence" do
      assert GuessElement.match?(title("Wonderwall - Remastered 2014"), "wonderwall by oasis")
    end

    test "allows small typos inside a sentence" do
      assert GuessElement.match?(title("Bohemian Rhapsody"), "is it bohemian rapsody")
      assert GuessElement.match?(artist("Oasis"), "wonderwall oassis")
    end

    test "allows joined or split words inside a sentence" do
      assert GuessElement.match?(title("Wonderwall"), "its wonder wall")
      assert GuessElement.match?(title("Bohemian Rhapsody"), "bohemianrhapsody by queen")
    end

    test "doesn't match part of a multi-word answer" do
      refute GuessElement.match?(title("Bohemian Rhapsody"), "something bohemian")
      refute GuessElement.match?(title("Hey Jude"), "hey you guys")
    end

    test "doesn't match unrelated messages" do
      refute GuessElement.match?(title("Wonderwall"), "no idea what this is")
      refute GuessElement.match?(artist("Oasis"), "sounds like the nineties")
    end

    test "matches short answers inside a message when spelled exactly" do
      assert GuessElement.match?(artist("Air"), "air")
      assert GuessElement.match?(artist("Yes"), "Yes!")
      assert GuessElement.match?(artist("Sia"), "sia chandelier")
      assert GuessElement.match?(artist("U2"), "u2 maybe")
    end

    test "doesn't allow typos in short answers inside a message" do
      refute GuessElement.match?(artist("Sia"), "sai chandelier")
      refute GuessElement.match?(artist("Air"), "a fair guess")
      refute GuessElement.match?(artist("U2"), "u 2 maybe")
    end
  end
end
