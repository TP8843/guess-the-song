import Config

# Route Last.fm/Deezer requests to Req.Test stubs instead of the real APIs,
# and don't retry, so error cases return straight away.
config :guess_the_song, :req_options,
  plug: {Req.Test, GuessTheSong.Api},
  retry: false
