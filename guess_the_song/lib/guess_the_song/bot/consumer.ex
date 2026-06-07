defmodule GuessTheSong.Bot.Consumer do
  @behaviour Nostrum.Consumer

  alias Nostrum.Api

  def handle_event({:READY, _data, _ws_state}) do
    IO.puts("Bot is ready! Registering commands...")
    GuessTheSong.Bot.Commands.register_all()
    IO.puts("Commands registered!")
  end

  def handle_event({:VOICE_READY, %{guild_id: guild_id}, _ws_state}) do
    case GuessTheSong.Voice.Supervisor.get_session(guild_id) do
      {:ok, pid} -> send(pid, :voice_ready)
      {:error, :not_found} -> :ignore
    end
  end

  def handle_event({:INTERACTION_CREATE, %{data: %{name: "start-quiz", options: options}} = interaction, _ws_state}) do
    text_channel_id = interaction.channel_id

    options = parse_options(options)

    case GuessTheSong.Voice.find_voice_channel(interaction.guild_id, interaction.member.user_id) do
      {:ok, voice_channel_id} ->
        case GuessTheSong.Quiz.Supervisor.start_session(
               interaction.guild_id,
               text_channel_id,
               voice_channel_id,
               options["rounds"]
             ) do
          {:ok, _pid} ->
            response = %{
              type: 4,
              data: %{
                content: "Started quiz! :D"
              }
            }

            Api.Interaction.create_response(interaction, response)

          {:error, :already_active} ->
            response = %{
              type: 4,
              data: %{
                content: "Quiz is already running!"
              }
            }

            Api.Interaction.create_response(interaction, response)
        end

      {:error, :not_in_voice_channel} ->
        response = %{
          type: 4,
          data: %{
            content: "You are not in a voice channel!"
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

  def handle_event(_event), do: :ok

  defp parse_options(options) do
    Enum.reduce(options, %{}, fn option, acc ->
      Map.put(acc, option.name, option.value)
    end)
  end
end
