defmodule GuessTheSong.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api.Message

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    IO.inspect(msg, label: "message received")
    case msg.content do
      "ping!" -> Message.create(msg.channel_id, "pong!")
      _ -> :ignore
    end
  end

  def handle_event(_event), do: :noop
  
end