defmodule GuessTheSong.Api.LastfmTest do
  use ExUnit.Case, async: true

  import GuessTheSong.Fixtures, only: [respond: 2, respond: 3]

  alias GuessTheSong.Api.Lastfm

  describe "fetch_user/1" do
    test "parses the user and asks for the right method" do
      Req.Test.stub(GuessTheSong.Api, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["method"] == "user.getinfo"
        assert conn.query_params["user"] == "testuser"
        assert conn.query_params["format"] == "json"
        respond(conn, "lastfm/user_getinfo")
      end)

      assert {:ok, user} = Lastfm.fetch_user("testuser")

      assert user == %Lastfm.User{
               name: "testuser",
               url: "https://www.last.fm/user/testuser",
               playcount: "12345",
               # The extralarge (4th) image
               image: "https://lastfm.freetls.fastly.net/i/u/300x300/abc.png"
             }
    end

    test "returns :not_found for an unknown user" do
      Req.Test.stub(GuessTheSong.Api, &respond(&1, "lastfm/user_not_found", 404))

      assert Lastfm.fetch_user("nobody") == {:error, :not_found}
    end

    test "returns other HTTP errors as they are" do
      Req.Test.stub(GuessTheSong.Api, &Plug.Conn.send_resp(&1, 429, "slow down"))

      assert Lastfm.fetch_user("testuser") == {:error, {:http_status, 429}}
    end

    test "returns :invalid_response for an unexpected body" do
      Req.Test.stub(GuessTheSong.Api, &Req.Test.json(&1, %{"something" => "else"}))

      assert Lastfm.fetch_user("testuser") == {:error, :invalid_response}
    end

    test "returns transport errors" do
      Req.Test.stub(GuessTheSong.Api, &Req.Test.transport_error(&1, :timeout))

      assert {:error, %Req.TransportError{reason: :timeout}} = Lastfm.fetch_user("testuser")
    end
  end

  describe "fetch_top_tracks/3" do
    test "parses every track and passes limit and period" do
      Req.Test.stub(GuessTheSong.Api, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["method"] == "user.gettoptracks"
        assert conn.query_params["user"] == "testuser"
        assert conn.query_params["limit"] == "50"
        assert conn.query_params["period"] == "7day"
        respond(conn, "lastfm/user_gettoptracks")
      end)

      assert {:ok, [first, second]} = Lastfm.fetch_top_tracks("testuser", 50, "7day")

      assert first == %Lastfm.Track{
               id: nil,
               title: "Wonderwall",
               artist: "Oasis",
               image_url: "https://lastfm.freetls.fastly.net/i/u/300x300/ww.png",
               url: "https://www.last.fm/music/Oasis/_/Wonderwall"
             }

      assert second.title == "Get Lucky (feat. Pharrell Williams & Nile Rodgers)"
      assert second.artist == "Daft Punk"
    end

    test "handles a single track returned as an object instead of a list" do
      [track | _] = GuessTheSong.Fixtures.load("lastfm/user_gettoptracks")["toptracks"]["track"]

      Req.Test.stub(
        GuessTheSong.Api,
        &Req.Test.json(&1, %{"toptracks" => %{"track" => track}})
      )

      assert {:ok, [%Lastfm.Track{title: "Wonderwall"}]} =
               Lastfm.fetch_top_tracks("testuser", 1, "overall")
    end

    test "returns an empty list when the user has no tracks" do
      Req.Test.stub(
        GuessTheSong.Api,
        &Req.Test.json(&1, %{"toptracks" => %{"track" => [], "@attr" => %{"total" => "0"}}})
      )

      assert Lastfm.fetch_top_tracks("testuser", 50, "7day") == {:ok, []}
    end

    test "returns HTTP errors" do
      Req.Test.stub(GuessTheSong.Api, &respond(&1, "lastfm/user_not_found", 404))

      assert Lastfm.fetch_top_tracks("nobody", 50, "7day") == {:error, {:http_status, 404}}
    end

    test "returns :invalid_response for an unexpected body" do
      Req.Test.stub(GuessTheSong.Api, &Req.Test.json(&1, %{"toptracks" => %{}}))

      assert Lastfm.fetch_top_tracks("testuser", 50, "7day") == {:error, :invalid_response}
    end
  end
end
