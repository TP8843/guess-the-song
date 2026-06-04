import Config
import Dotenvy

IO.puts(Path.absname(".env", File.cwd!()))

source!([
  Path.absname(".env", File.cwd!()),
  System.get_env()
])

config :guess_the_song,
  token: env!("BOT_TOKEN", :string!),
  guild: env!("GUILD", :string),
  gateway_intents: [
    :guilds,
    :guild_messages,
    :guild_voice_states,
    # required to read message content
    :message_content
  ]
