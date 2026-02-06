package commands

import (
	"fmt"
	"guess-the-song-discord/internal/state/tracks"
	"log"

	"github.com/bwmarrin/discordgo"
)

func (ctx *Context) HandleMessage(s *discordgo.Session, i *discordgo.MessageCreate) {
	// If no state is running, ignore
	if !ctx.quizState.HasQuiz(i.GuildID) {
		return
	}

	quiz, err := ctx.quizState.GetQuiz(i.GuildID)
	if err != nil {
		log.Println(fmt.Errorf("could not get state: %w", err))
		return
	}

	results := quiz.ProcessGuess(i.ChannelID, i.Author.ID, i.Content)

	if len(results) > 0 {
		_, err := s.ChannelMessageSendEmbedReply(
			i.ChannelID,
			ctx.buildCorrectGuessEmbed(results),
			i.SoftReference(),
		)
		if err != nil {
			log.Println(fmt.Errorf("could not send message: %w", err))
		}
	}
}

func (ctx *Context) buildCorrectGuessEmbed(results []*tracks.GuessElement) *discordgo.MessageEmbed {
	messageEmbed := &discordgo.MessageEmbed{
		Title:  "Correct!",
		Fields: []*discordgo.MessageEmbedField{},
	}

	for _, result := range results {
		plural := ""
		if result.GetPoints() != 1 {
			plural = "s"
		}

		messageEmbed.Fields = append(messageEmbed.Fields, &discordgo.MessageEmbedField{
			Value: fmt.Sprintf(
				"%s is **%s** (+%d point%s)",
				result.GetCategory(),
				result.GetValue(),
				result.GetPoints(),
				plural,
			),
		})
	}

	return messageEmbed
}
