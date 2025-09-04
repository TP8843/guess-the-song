package commands

import (
	"fmt"
	"log"

	"github.com/bwmarrin/discordgo"
)

func (ctx *Context) HandleMessage(s *discordgo.Session, i *discordgo.MessageCreate) {
	// If no quiz is running, ignore
	if !ctx.quizState.HasQuiz(i.GuildID) {
		return
	}

	quiz, err := ctx.quizState.GetQuiz(i.GuildID)
	if err != nil {
		log.Println(fmt.Errorf("could not get quiz: %w", err))
		return
	}

	result := quiz.ProcessGuess(i.ChannelID, i.Author.ID, i.Content)

	if result != nil {
		_, err := s.ChannelMessageSendEmbedReply(
			i.ChannelID,
			ctx.buildCorrectGuessEmbed(result.GetCategory(), result.GetValue(), result.GetPoints()),
			i.SoftReference(),
		)
		if err != nil {
			log.Println(fmt.Errorf("could not send message: %w", err))
		}
	}
}

func (ctx *Context) buildCorrectGuessEmbed(category, value string, points int) *discordgo.MessageEmbed {
	plural := ""
	if points != 1 {
		plural = "s"
	}

	return &discordgo.MessageEmbed{
		Description: fmt.Sprintf(
			"Correct! %s is **%s** (+%d point%s)",
			category,
			value,
			points,
			plural,
		),
	}
}
