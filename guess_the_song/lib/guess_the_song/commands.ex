defmodule GuessTheSong.Commands do
  def init_application_commands do
    commands = [
      %{
        name: "test",
        description: "test command",
      }
    ]

    guild = Application.get_env(:nostrum, :guild)
    if guild != nil and String.length(guild) > 0 do
      IO.puts(guild)
      Enum.each(commands, fn command -> 
        Nostrum.Api.ApplicationCommand.create_guild_command(guild, command)
      end)
    else
      Enum.each(commands, fn command -> 
        Nostrum.Api.ApplicationCommand.create_global_command(command)
      end)
    end
  end
end