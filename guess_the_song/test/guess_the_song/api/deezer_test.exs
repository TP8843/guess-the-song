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

    assert_received {:search, %{"q" => "Get Lucky Daft Punk", "limit" => "1"}}
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

  test "returns transport errors" do
    stub_api(fixture("deezer/search"), &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             Deezer.find_match(@lastfm_track)
  end
end
