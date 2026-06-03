import Config
import Dotenvy

IO.puts(Path.absname(".env", File.cwd!()))

source!([
  Path.absname(".env", File.cwd!()),
  System.get_env()
])

config :nostrum,
  token: env!("BOT_TOKEN", :string!),
  guild: env!("GUILD", :string),
  gateway_intents: [
    :guilds,
    :guild_messages,
    # required to read message content
    :message_content
  ]
