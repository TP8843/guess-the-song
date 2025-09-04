# Guess the Song Discord Bot

A multiplayer music quiz bot for Discord voice channels. The bot plays short snippets of 
songs and challenges users to guess the track and artist. It integrates with the Last.fm 
API to source users' most played tracks and uses Deezer for song previews.

## Features

- Plays audio snippets in the user's current voice channel (backed by FFmpeg)
- Slash command–driven UX (registered automatically on startup)
- Configurable via either CLI flags or environment variables
- Last.fm integration for music metadata
- Single-guild testing mode during development

## Prerequisites

- Go (1.25+)
- FFmpeg (must be installed and available in PATH)
- GCC (required for CGO, e.g. MinGW on Windows)
- Discord bot token with correct permissions
- Last.fm API key and shared secret

Windows specific:
- Install GCC via MinGW: https://code.visualstudio.com/docs/cpp/config-mingw
- Ensure ffmpeg.exe is in your PATH (verify using `ffmpeg -version` in a new terminal)

Enable CGO support: 
- `go env -w CGO_ENABLED=1`

## Installation

1. Install Go
2. Install FFmpeg
3. Install GCC
4. Enable CGO support: `go env -w CGO_ENABLED=1`
5. Clone and build the project:
   - `go build ./`
6. Ensure FFmpeg is in your PATH
    - macOS/Linux: `ffmpeg -version`
    - Windows (PowerShell): `Get-Command ffmpeg`

## Configuration

You can configure the bot using either command-line arguments or environment variables.

- Arguments:
    - `-token` discord_token
    - `-lastfm_key` lastfm_api_key
    - `-lastfm_secret` lastfm_shared_secret
    - `-guild` id_of_guild_for_testing (leave empty to register commands globally)
- Environment Variables (fallback if arguments are not available):
    - `BOT_TOKEN` — Discord bot token
    - `LASTFM_KEY` — Last.fm API key
    - `LASTFM_SECRET` — Last.fm shared secret
    - `GUILD_ID` — ID of a guild (server) for command registration during development

>[!Tip]
> - During development, prefer using a single test guild (`-guild` or `GUILD_ID`) to register slash commands instantly.
> - Global command registration can take up to an hour to propagate.

## Quick Start

### Using arguments:
macOS/Linux:
- `./guess-the-song-discord -token "YOUR_DISCORD_TOKEN" -lastfm_key "YOUR_LASTFM_KEY" -lastfm_secret "YOUR_LASTFM_SECRET" -guild "YOUR_GUILD_ID"`

Windows (PowerShell):
- `.\guess-the-song-discord.exe -token "YOUR_DISCORD_TOKEN" -lastfm_key "YOUR_LASTFM_KEY" -lastfm_secret "YOUR_LASTFM_SECRET" -guild "YOUR_GUILD_ID"`

### Using environment variables:

macOS/Linux:
```shell
export BOT_TOKEN="YOUR_DISCORD_TOKEN"
export LASTFM_KEY="YOUR_LASTFM_KEY"
export LASTFM_SECRET="YOUR_LASTFM_SECRET"
export GUILD_ID="YOUR_GUILD_ID"
./guess-the-song-discord
```

Windows (PowerShell):
```shell
$env:BOT_TOKEN="YOUR_DISCORD_TOKEN"
$env:LASTFM_KEY="YOUR_LASTFM_KEY"
$env:LASTFM_SECRET="YOUR_LASTFM_SECRET"
$env:GUILD_ID="YOUR_GUILD_ID"
.\guess-the-song-discord.exe
```

When running, you should see: “Bot is now running. Press CTRL-C to exit.”
