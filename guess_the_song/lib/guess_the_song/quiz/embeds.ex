defmodule GuessTheSong.Quiz.Embeds do

  def correct_guess(guess_element) do
    %Nostrum.Struct.Embed{
      description: "Correct! **#{guess_element.type}** is **#{guess_element.string}** (+#{guess_element.value})",
      color: 0x00F400
    }
  end

  def round_end(track, scores) do
    %Nostrum.Struct.Embed{
      title: "#{track.deezer.title}",
      author: %Nostrum.Struct.Embed.Author{
        name: track.source.name,
        icon_url: track.source.image,
        url: track.source.url,
      },
      url: track.deezer.url,
      description: Enum.map(track.deezer.artists, fn artist ->
        "[#{artist.name}](#{artist.url})"
      end) |> Enum.join(", "),
      fields: [
        %Nostrum.Struct.Embed.Field{
          name: "Current Scores:",
          value: generate_scores_string(scores),
          inline: false
        }
      ],
      thumbnail: %Nostrum.Struct.Embed.Image{
        url: track.deezer.cover
      },
      color: 0xFFFF00
    }
  end

  def generate_scores_string(scores) do
    Enum.reduce(scores, "", fn {user_id, score}, acc ->
      acc <> "- <@#{user_id}> - #{score}"
    end)
  end

  def game_end(scores) do
    %Nostrum.Struct.Embed{
      title: "Game End",
      fields: [
        %Nostrum.Struct.Embed.Field{
          name: "Final Scores:",
          value: generate_scores_string(scores),
          inline: false
        }
      ],
      color: 0xFFFF00
    }
  end
end
