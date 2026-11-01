defmodule GuessTheSong.Bot.Commands do
  alias GuessTheSong.Bot.Commands.Definitions
  alias Nostrum.Api.ApplicationCommand

  @registered_key {__MODULE__, :registered}

  @doc """
  Registers the commands, unless they have already been registered since the
  bot started. `READY` fires again on every full reconnect, so this skips the
  repeat registrations. It's only marked as done on success, so a failed
  attempt is retried on the next `READY`.
  """
  def register_once do
    if :persistent_term.get(@registered_key, false) do
      :already_registered
    else
      case register_all() do
        {:ok, _commands} ->
          :persistent_term.put(@registered_key, true)
          :ok

        {:error, reason} ->
          IO.inspect(reason, label: "Failed to register commands")
          {:error, reason}
      end
    end
  end

  # Replaces all of the bot's commands in one request. This also removes any
  # commands that are no longer in `Definitions`.
  def register_all do
    guild = Application.get_env(:guess_the_song, :guild)

    if guild != nil and String.length(guild) > 0 do
      ApplicationCommand.bulk_overwrite_guild_commands(guild, Definitions.all())
    else
      ApplicationCommand.bulk_overwrite_global_commands(Definitions.all())
    end
  end
end
