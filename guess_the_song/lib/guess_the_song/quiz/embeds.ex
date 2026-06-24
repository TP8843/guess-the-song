defmodule GuessTheSong.Quiz.Embeds do
  def error(message) do
    %Nostrum.Struct.Embed{
      title: "**Error:** #{message}",
      color: 0xF40000
    }
  end

  def link_account_success(user) do
    %Nostrum.Struct.Embed{
      title: "Linked account: #{user.name}",
      thumbnail: %Nostrum.Struct.Embed.Image{url: user.image},
      color: 0x00F400,
      fields: []
    }
  end

  def link_account_failure do
    %Nostrum.Struct.Embed{
      title: "Failed to link Last.fm account",
      description: "Last.fm account not found",
      color: 0xF40000
    }
  end

  def unlink_account_success(lastfm_username) do
    %Nostrum.Struct.Embed{
      title: "Unlinked account: #{lastfm_username}",
      color: 0x00F400,
      fields: []
    }
  end

  def unlink_account_failure do
    %Nostrum.Struct.Embed{
      title: "Failed to unlink Last.fm account",
      description: "No account linked",
      color: 0xF40000
    }
  end

  def starting(sources) do
    %Nostrum.Struct.Embed{
      title: "Starting Quiz",
      fields: [
        %Nostrum.Struct.Embed.Field{
          name: "Sources",
          value:
            Enum.reduce(sources, "", fn source, acc ->
              acc <>
                "[#{source.lastfm_username}](https://www.last.fm/user/#{source.lastfm_username})" <>
                " "
            end),
          inline: false
        }
      ],
      color: 0x00F400
    }
  end

  def correct_guess(guess_element) do
    %Nostrum.Struct.Embed{
      description:
        "Correct! **#{guess_element.type}** is **#{guess_element.string}** (+#{guess_element.value})",
      color: 0x00F400
    }
  end

  def round_end(guild_id, track, round_scores, scores) do
    %Nostrum.Struct.Embed{
      title: "#{track.deezer.title}",
      author: %Nostrum.Struct.Embed.Author{
        name: track.source.name,
        icon_url: track.source.image,
        url: track.source.url
      },
      url: track.deezer.url,
      description:
        Enum.map(track.deezer.artists, fn artist ->
          "[#{artist.name}](#{artist.url})"
        end)
        |> Enum.join(", "),
      fields: [
        %Nostrum.Struct.Embed.Field{
          name: "Current Scores:",
          value: generate_scores_string(guild_id, scores, round_scores),
          inline: false
        }
      ],
      thumbnail: %Nostrum.Struct.Embed.Image{
        url: track.deezer.cover
      },
      color: 0xFFFF00
    }
  end

  def generate_scores_string(guild_id, scores, round_scores \\ %{}) do
    Enum.reduce(scores, "", fn {user_id, score}, acc ->
      {:ok, user} = Nostrum.Cache.MemberCache.get(guild_id, user_id)

      case Map.has_key?(round_scores, user_id) do
        true -> acc <> "- **#{user.nick} - #{score}** (+#{round_scores[user_id]})"
        false -> acc <> "- **#{user.nick} - #{score}**"
      end
    end)
  end

  def game_end(guild_id, scores) do
    %Nostrum.Struct.Embed{
      title: "Game End",
      fields: [
        %Nostrum.Struct.Embed.Field{
          name: "Final Scores:",
          value: generate_scores_string(guild_id, scores),
          inline: false
        }
      ],
      color: 0xFFFF00
    }
  end
end
