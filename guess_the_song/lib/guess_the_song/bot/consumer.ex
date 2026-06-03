defmodule GuessTheSong.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  def handle_event({:READY, _data, _ws_state}) do
    IO.puts("Bot is ready! Registering commands...")
    GuessTheSong.Commands.register_all()
    IO.puts("Commands registered!")
  end

  def handle_event({:INTERACTION_CREATE, %{data: %{name: "start-quiz"}} = interaction, _ws_state}) do
    case GuessTheSong.QuizServerSupervisor.start_session(interaction.guild_id) do
      {:ok, _pid} ->
        response = %{
          type: 4,
          data: %{
            content: "Started quiz! :D"
          }
        }
        Api.Interaction.create_response(interaction, response)

      {:error, :already_started} ->
        response = %{
          type: 4,
          data: %{
            content: "Quiz is already running!"
          }
        }
        Api.Interaction.create_response(interaction, response)
    end
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

  def handle_event({:INTERACTION_CREATE, %{data: %{name: "echo"}} = interaction, _ws_state}) do
    response = %{
      type: 4,
      data: %{
        content: Enum.at(interaction.data.options, 0).value
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case msg.content do
      "ping!" -> Api.Message.create(msg.channel_id, "pong!")
      _ -> :ignore
    end
  end

  def handle_event(_event), do: :noop
end
