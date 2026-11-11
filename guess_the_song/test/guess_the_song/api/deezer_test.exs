defmodule GuessTheSong.Api.DeezerTest do
  use ExUnit.Case, async: true

  import GuessTheSong.Fixtures, only: [respond: 2]

  alias GuessTheSong.Api.{Deezer, Lastfm}

  @lastfm_track %Lastfm.Track{title: "Get Lucky", artist: "Daft Punk"}

  # Answers the search and track lookups with the given responses
  defp stub_api(search, track) do
    Req.Test.stub(GuessTheSong.Api, fn conn ->
      case conn.request_path do
        "/search" -> search.(conn)
        "/track/" <> _id -> track.(conn)
      end
    end)
  end

  defp fixture(name), do: &respond(&1, name)

  test "searches for the track, then fetches it by ID" do
    test_pid = self()

    stub_api(
      fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(test_pid, {:search, conn.query_params})
        respond(conn, "deezer/search")
      end,
      fn conn ->
        send(test_pid, {:track, conn.request_path})
        respond(conn, "deezer/track")
      end
    )

    assert {:ok, track} = Deezer.find_match(@lastfm_track)

    assert_received {:search, %{"q" => ~s(artist:"Daft Punk" track:"Get Lucky"), "limit" => "10"}}
    # The strict search found a match, so no fuzzy search
    refute_received {:search, _}
    assert_received {:track, "/track/67238735"}

    assert track.id == 67_238_735
    assert track.title == "Get Lucky (feat. Pharrell Williams and Nile Rodgers)"
    assert track.url == "https://www.deezer.com/track/67238735"
    assert track.preview == "https://cdnt-preview.dzcdn.net/api/1/1/a/b/c/0/getlucky.mp3"
    assert track.cover == "https://api.deezer.com/album/6575789/image"
  end

  test "marks the track's artist as main and other contributors as featured" do
    stub_api(fixture("deezer/search"), fixture("deezer/track"))

    assert {:ok, track} = Deezer.find_match(@lastfm_track)

    assert [
             %Deezer.Artist{id: 27, name: "Daft Punk", role: :main},
             %Deezer.Artist{id: 4429, name: "Pharrell Williams", role: :feat},
             %Deezer.Artist{id: 2276, name: "Nile Rodgers", role: :feat}
           ] = track.artists
  end

  test "returns :not_found when the search has no results" do
    stub_api(fixture("deezer/search_empty"), fn _ -> flunk("shouldn't fetch a track") end)

    assert Deezer.find_match(@lastfm_track) == {:error, :not_found}
  end

  # Deezer reports errors as a 200 with an "error" body
  test "returns :invalid_response for a quota error during the search" do
    stub_api(fixture("deezer/quota_error"), fn _ -> flunk("shouldn't fetch a track") end)

    assert Deezer.find_match(@lastfm_track) == {:error, :invalid_response}
  end

  test "returns :invalid_response for a quota error during the track lookup" do
    stub_api(fixture("deezer/search"), fixture("deezer/quota_error"))

    assert Deezer.find_match(@lastfm_track) == {:error, :invalid_response}
  end

  test "returns :invalid_response when the track no longer exists" do
    stub_api(fixture("deezer/search"), fixture("deezer/track_not_found"))

    assert Deezer.find_match(@lastfm_track) == {:error, :invalid_response}
  end

  test "returns HTTP errors" do
    stub_api(&Plug.Conn.send_resp(&1, 503, "unavailable"), fn _ -> flunk("unexpected") end)

    assert Deezer.find_match(@lastfm_track) == {:error, {:http_status, 503}}
  end

  describe "choosing a search result" do
    # A search result, Get Lucky by Daft Punk unless overridden
    defp result(id, overrides \\ %{}) do
      Map.merge(
        %{
          "id" => id,
          "readable" => true,
          "title" => "Get Lucky",
          "title_short" => "Get Lucky",
          "rank" => 500_000,
          "preview" => "https://cdnt-preview.dzcdn.net/#{id}.mp3",
          "artist" => %{"id" => 27, "name" => "Daft Punk"},
          "album" => %{"title" => "Random Access Memories"}
        },
        overrides
      )
    end

    defp search_results(conn, results), do: Req.Test.json(conn, %{"data" => results})

    # Serves `exact` for the strict search and `fuzzy` for the fuzzy one, and
    # reports which track ID was fetched
    defp stub_searches(exact, fuzzy) do
      test_pid = self()

      stub_api(
        fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)
          send(test_pid, {:search, conn.query_params["q"]})

          if String.starts_with?(conn.query_params["q"], "artist:"),
            do: search_results(conn, exact),
            else: search_results(conn, fuzzy)
        end,
        fn conn ->
          send(test_pid, {:fetched, conn.request_path})
          respond(conn, "deezer/track")
        end
      )
    end

    defp find(lastfm_track \\ @lastfm_track) do
      result = Deezer.find_match(lastfm_track)

      receive do
        {:fetched, "/track/" <> id} -> {result, String.to_integer(id)}
      after
        0 -> result
      end
    end

    test "falls back to the fuzzy search when the strict search finds nothing" do
      stub_searches([], [result(2)])

      assert {{:ok, _}, 2} = find()
      assert_received {:search, "artist:" <> _}
      assert_received {:search, "Get Lucky Daft Punk"}
    end

    test "falls back to the fuzzy search when the strict results don't match" do
      stub_searches(
        [result(1, %{"title" => "Something Else", "title_short" => "Something Else"})],
        [result(2)]
      )

      assert {{:ok, _}, 2} = find()
    end

    test "returns :not_found when no result is similar enough" do
      stub_searches(
        [result(1, %{"artist" => %{"name" => "Someone Else"}})],
        [result(2, %{"title" => "Lose Yourself to Dance", "title_short" => nil})]
      )

      assert find() == {:error, :not_found}
      refute_received {:fetched, _}
    end

    test "prefers a matching result over a higher-placed wrong one" do
      stub_searches(
        [result(1, %{"artist" => %{"name" => "Daft Punk Tribute Band"}}), result(2)],
        []
      )

      assert {{:ok, _}, 2} = find()
    end

    test "rejects karaoke and tribute versions" do
      stub_searches(
        [
          result(1, %{"title" => "Get Lucky (Karaoke Version)"}),
          result(2, %{"album" => %{"title" => "Originally Performed by Daft Punk"}})
        ],
        []
      )

      assert find() == {:error, :not_found}
    end

    test "prefers the original over a live version or remix" do
      stub_searches(
        [
          result(1, %{"title" => "Get Lucky (Live)", "rank" => 900_000}),
          result(2, %{"title" => "Get Lucky (Remix)", "rank" => 800_000}),
          result(3, %{"rank" => 100_000})
        ],
        []
      )

      assert {{:ok, _}, 3} = find()
    end

    test "accepts a version the Last.fm title asks for" do
      stub_searches(
        [
          result(1, %{"title" => "Get Lucky (Radio Edit)"}),
          result(2, %{"title" => "Get Lucky (Live)"})
        ],
        []
      )

      assert {{:ok, _}, 2} = find(%Lastfm.Track{title: "Get Lucky (Live)", artist: "Daft Punk"})
    end

    test "breaks ties by popularity" do
      stub_searches([result(1, %{"rank" => 1_000}), result(2, %{"rank" => 900_000})], [])

      assert {{:ok, _}, 2} = find()
    end

    test "skips results without a playable preview" do
      stub_searches(
        [result(1, %{"preview" => ""}), result(2, %{"readable" => false}), result(3)],
        []
      )

      assert {{:ok, _}, 3} = find()
    end

    test "matches despite different version suffixes" do
      stub_searches(
        [result(1, %{"title" => "Get Lucky (feat. Pharrell Williams and Nile Rodgers)"})],
        []
      )

      assert {{:ok, _}, 1} =
               find(%Lastfm.Track{title: "Get Lucky - Radio Edit", artist: "Daft Punk"})
    end

    test "matches the main artist when Last.fm lists several" do
      stub_searches([result(1)], [])

      assert {{:ok, _}, 1} =
               find(%Lastfm.Track{title: "Get Lucky", artist: "Daft Punk & Pharrell Williams"})
    end

    test "removes double quotes from the strict search" do
      stub_searches([result(1, %{"title" => ~s(The "Song")})], [])

      find(%Lastfm.Track{title: ~s(The "Song"), artist: "Daft Punk"})

      assert_received {:search, ~s(artist:"Daft Punk" track:"The  Song ")}
    end
  end

  test "returns transport errors" do
    stub_api(fixture("deezer/search"), &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             Deezer.find_match(@lastfm_track)
  end
end
