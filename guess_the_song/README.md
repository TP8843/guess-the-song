# GuessTheSong

A Discord bot that runs music quizzes in voice channels. It picks tracks from
players' linked Last.fm libraries and plays Deezer previews for them to guess.

## Requirements

- Erlang and Elixir (versions in `mise.toml`; run `mise install`)
- `ffmpeg` (used for voice playback)

## Configuration

Create a `.env` file in this directory (or export the variables):

```bash
BOT_TOKEN=...        # Discord bot token
LASTFM_KEY=...       # Last.fm API key
LASTFM_SECRET=...    # Last.fm API secret
DATABASE=guess_the_song.db  # SQLite database path
GUILD=...            # Optional: register commands to one server (faster updates while developing)
```

## Commands

```bash
mix deps.get         # Install dependencies
mix ecto.create      # Create the SQLite database file
mix ecto.migrate     # Create/update tables (safe to re-run)
mix ecto.migrations  # Show which migrations have run

iex -S mix           # Run the bot with an interactive shell
mix run --no-halt    # Run the bot without a shell

mix compile          # Compile and show warnings
mix format           # Format the code
mix test             # Run the tests
```

If `mix` isn't on your `PATH`, prefix commands with `mise exec --`.

## Docker

```bash
docker build -t guess_the_song .
docker run --env-file .env guess_the_song
```

The container runs migrations on startup. Point `DATABASE` at a mounted volume
(writable by the `nobody` user) to keep data between restarts.
