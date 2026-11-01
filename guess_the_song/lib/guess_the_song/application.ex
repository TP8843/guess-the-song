defmodule GuessTheSong.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    bot_options = %{
      name: GuessTheSong,
      consumer: GuessTheSong.Bot.Consumer,
      intents: Application.get_env(:guess_the_song, :gateway_intents),
      wrapped_token: fn -> Application.get_env(:guess_the_song, :token) end
    }

    # Children start in order and stop in reverse order
    children = [
      # Start the database first, so it's ready before any Discord events arrive
      {GuessTheSong.DB.Repo, []},
      {Registry, keys: :unique, name: GuessTheSong.Quiz.Registry},
      # Runs slow work (Last.fm/Deezer fetches) for quiz servers
      {Task.Supervisor, name: GuessTheSong.Quiz.TaskSupervisor},
      {GuessTheSong.Quiz.Supervisor, []},
      {Registry, keys: :unique, name: GuessTheSong.Voice.Registry},
      {GuessTheSong.Voice.Supervisor, []},
      # Start the bot last, so everything its events use is already running
      {Nostrum.Bot, bot_options}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GuessTheSong.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
