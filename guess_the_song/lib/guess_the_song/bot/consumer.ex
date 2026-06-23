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
      {:ok, {pid, _}} -> send(pid, :voice_ready)
      {:ok, pid} -> send(pid, :voice_ready)
      {:error, :not_found} -> :ignore
    end
  end

  def handle_event({:VOICE_SPEAKING_UPDATE, %{speaking: false, guild_id: guild_id}, _ws_state}) do
    # Audio has finished playing!
    case GuessTheSong.Quiz.Supervisor.active?(guild_id) do
      true -> GuessTheSong.Quiz.Server.end_round(guild_id)
      false -> :ok
    end
  end

  def handle_event({:VOICE_SPEAKING_UPDATE, %{speaking: true, guild_id: _guild_id}, _ws_state}) do
    # Audio started playing
    :ok
  end

  def handle_event(
        {:INTERACTION_CREATE, %{data: %{name: "link", options: options}} = interaction, _ws_state}
      ) do

    Api.Interaction.create_response(interaction, %{type: 5})
    options = parse_options(options)

    Task.async(fn ->
      case GuessTheSong.Api.Lastfm.fetch_user(options["lastfm"]) do
        {:ok, user} ->
          case GuessTheSong.DB.User
               |> GuessTheSong.DB.Repo.get_by(discord_id: interaction.user.id) do
            nil ->
              db_user = %GuessTheSong.DB.User{
                discord_id: interaction.user.id,
                lastfm_username: user.name
              }

              GuessTheSong.DB.Repo.insert!(db_user)

            db_user ->
              changeset = GuessTheSong.DB.User.changeset(db_user, %{lastfm_username: user.name})
              GuessTheSong.DB.Repo.update(changeset)
          end

          Api.Interaction.edit_response(interaction, %{
            type: 7,
            embeds: [GuessTheSong.Quiz.Embeds.link_account_success(user)]
          })

        {:error, :not_found} ->
          Api.Interaction.edit_response(interaction, %{
            type: 7,
            embeds: [GuessTheSong.Quiz.Embeds.link_account_failure()]
          })

        {:error, reason} ->
          IO.inspect(reason)

          Api.Interaction.edit_response(interaction, %{
            type: 7,
            embeds: [GuessTheSong.Quiz.Embeds.error("Failed to link Last.fm account.")]
          })
      end
    end)

    :ok
  end

  def handle_event({:INTERACTION_CREATE, %{data: %{name: "unlink"}} = interaction, _ws_state}) do
    alias GuessTheSong.DB

    Api.Interaction.create_response(interaction, %{type: 5})

    case DB.User
         |> DB.Repo.get_by(discord_id: interaction.member.user_id) do
      nil ->
        Api.Interaction.edit_response(interaction, %{
          type: 7,
          embeds: [GuessTheSong.Quiz.Embeds.unlink_account_failure()]
        })

      user ->
        DB.Repo.delete(user)

        Api.Interaction.edit_response(interaction, %{
          type: 7,
          embeds: [GuessTheSong.Quiz.Embeds.unlink_account_success(user.lastfm_username)]
        })
    end
  end

  def handle_event(
        {:INTERACTION_CREATE, %{data: %{name: "start-quiz", options: options}} = interaction,
         _ws_state}
      ) do

      # Defer the response to avoid timeout
    Api.Interaction.create_response(interaction, %{type: 5})
    text_channel_id = interaction.channel_id

    options = parse_options(options)

    case GuessTheSong.Voice.find_voice_channel(interaction.guild_id, interaction.member.user_id) do
      {:ok, voice_channel_id} ->
        case GuessTheSong.Quiz.Supervisor.start_session(
               interaction,
               interaction.guild_id,
               text_channel_id,
               voice_channel_id,
               options["rounds"]
             ) do
          {:ok, _pid} -> :ok
          {:error, :already_active} ->
            response = %{
              type: 7,
              embeds: [GuessTheSong.Quiz.Embeds.error("Bot is already running in this server")]
            }

            Api.Interaction.edit_response(interaction, response)
        end

      {:error, :not_in_voice_channel} ->
        response = %{
          type: 7,
          embeds: [GuessTheSong.Quiz.Embeds.error("You are not in a voice channel!")]
        }

        Api.Interaction.edit_response(interaction, response)
    end
  end

  def handle_event({:INTERACTION_CREATE, %{data: %{name: "end-quiz"}} = interaction, _ws_state}) do
    if GuessTheSong.Quiz.Supervisor.active?(interaction.guild_id) do
      response = %{
        type: 4,
        data: %{
          content: "Ending quiz..."
        }
      }

      Api.Interaction.create_response(interaction, response)

      GuessTheSong.Quiz.Supervisor.stop_session(interaction.guild_id)
    else
      response = %{
        type: 4,
        data: %{
          content: "No quiz is currently running!"
        }
      }

      Api.Interaction.create_response(interaction, response)
    end
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    # Check if message sent from channel used for quiz
    case GuessTheSong.Quiz.Supervisor.get_session(msg.guild_id) do
      {:ok, {_, %{text_channel_id: text_channel_id}}} ->
        if msg.author.id != Nostrum.Cache.Me.get().id && msg.channel_id == text_channel_id do
          GuessTheSong.Quiz.Server.process_message(msg.guild_id, msg)
        end

        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  def handle_event(_event), do: :ok

  defp parse_options(options) do
    Enum.reduce(options, %{}, fn option, acc ->
      Map.put(acc, option.name, option.value)
    end)
  end
end
