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

    children = [
      # Starts a worker by calling: GuessTheSong.Worker.start_link(arg)
      # {GuessTheSong.Worker, arg}
      # {Nostrum.Bot, bot_options}

      {Registry, keys: :unique, name: GuessTheSong.Quiz.Registry},
      {GuessTheSong.Quiz.Supervisor, []},
      {Registry, keys: :unique, name: GuessTheSong.Voice.Registry},
      {GuessTheSong.Voice.Supervisor, []},
      # GuessTheSong.Bot.Consumer
      {Nostrum.Bot, bot_options},
      {GuessTheSong.DB.Repo, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GuessTheSong.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
