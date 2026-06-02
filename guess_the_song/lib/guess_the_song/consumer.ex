defmodule GuessTheSong.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  def handle_event({:READY, _data, _ws_state}) do
    IO.puts("Bot is ready! Registering commands...")
    GuessTheSong.Commands.init_application_commands()
    IO.puts("Commands registered!")
  end

  def handle_event({:INTERACTION_CREATE, %{data: %{name: "test"}} = interaction, _ws_state}) do
    response = %{
      type: 4,
      data: %{
        content: "Hello, World!"
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    IO.inspect(msg, label: "message received")
    case msg.content do
      "ping!" -> Api.Message.create(msg.channel_id, "pong!")
      _ -> :ignore
    end
  end

  def handle_event(_event), do: :noop
  
end