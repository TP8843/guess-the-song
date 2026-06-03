defmodule GuessTheSong.Commands do
  alias GuessTheSong.Bot.Commands.Definitions

  def register_all do
    guild = Application.get_env(:nostrum, :guild)

    if guild != nil and String.length(guild) > 0 do
      Enum.each(Definitions.all(), fn command ->
        Nostrum.Api.ApplicationCommand.create_guild_command(guild, command)
      end)
    else
      Enum.each(Definitions.all(), fn command ->
        Nostrum.Api.ApplicationCommand.create_global_command(command)
      end)
    end
  end
end
