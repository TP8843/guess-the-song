defmodule GuessTheSong.Bot.Commands.Definitions do
  def all do
    [
      %{
        name: "test",
        description: "test command"
      },
      %{
        name: "echo",
        description: "echo response back",
        options: [
          %{
            name: "message",
            description: "message to echo",
            type: 3,
            required: true
          }
        ]
      },
      %{
        name: "start-quiz",
        description: "starts a new guess the song quiz",
        options: [
          %{
            name: "rounds",
            description: "number of rounds to play",
            type: 4,
            min_value: 1,
            max_value: 100,
            required: true
          }
        ]
      }
    ]
  end
end
