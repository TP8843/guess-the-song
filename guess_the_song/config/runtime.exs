import Config
import Dotenvy

IO.puts(Path.absname(".env", File.cwd!()))

source!([
  Path.absname(".env", File.cwd!()),
  System.get_env()
])

config :nostrum,
  token: env!("BOT_TOKEN", :string!),
  gateway_intents: [
    :guilds,
    :guild_messages,
    :message_content  # required to read message content
  ]
