import Config

config :guess_the_song,
  ecto_repos: [GuessTheSong.DB.Repo]

# Per-environment overrides (e.g. config/test.exs), if the file exists
if File.exists?(Path.join(__DIR__, "#{config_env()}.exs")) do
  import_config "#{config_env()}.exs"
end
