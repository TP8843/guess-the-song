defmodule GuessTheSong.Bot.Commands.Definitions do
  def all do
    [
      %{
        name: "link",
        description: "link your last.fm account to your Discord account",
        options: [
          %{
            name: "lastfm",
            description: "your last.fm username",
            type: 3,
            required: true
          }
        ]
      },
      %{
        name: "unlink",
        description: "unlink your last.fm account from your Discord account",
        options: []
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
      },
      %{
        name: "end-quiz",
        description: "ends the current quiz"
      }
    ]
  end
end
