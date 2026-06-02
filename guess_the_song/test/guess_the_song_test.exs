defmodule GuessTheSongTest do
  use ExUnit.Case
  doctest GuessTheSong

  test "greets the world" do
    assert GuessTheSong.hello() == :world
  end
end
