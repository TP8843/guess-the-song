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
          },
          %{
            name: "tracks-per-user",
            description: "number of tracks to use per user",
            type: 4,
            min_value: 1,
            max_value: 1000,
            required: true
          },
          %{
            name: "period",
            description: "period of time to query for top tracks",
            type: 3,
            choices: [
              %{name: "week", value: "7day"},
              %{name: "1 month", value: "1month"},
              %{name: "3 months", value: "3month"},
              %{name: "6 months", value: "6month"},
              %{name: "1 year", value: "12month"},
              %{name: "overall", value: "overall"}
            ],
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
