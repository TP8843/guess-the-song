package commands

import (
	"fmt"
	"log"

	"github.com/bwmarrin/discordgo"
)

func (context *Context) HandleMessage(s *discordgo.Session, i *discordgo.MessageCreate) {
	// If no quiz is running, ignore
	if !context.quizState.HasQuiz(i.GuildID) {
		return
	}

	quiz, err := context.quizState.GetQuiz(i.GuildID)
	if err != nil {
		log.Println(fmt.Errorf("could not get quiz: %w", err))
	}

	result := quiz.ProcessGuess(i.ChannelID, i.Author.ID, i.Content)

	if result != nil {
		var plural = 's'

		if result.GetPoints() == 1 {
			plural = '\000'
		}

		_, err := s.ChannelMessageSendEmbedReply(i.ChannelID, &discordgo.MessageEmbed{
			Description: fmt.Sprintf("Correct! %s is **%s** (+%d point%c)",
				result.GetCategory(),
				result.GetValue(),
				result.GetPoints(),
				plural,
			),
		}, i.SoftReference())
		if err != nil {
			log.Println(fmt.Errorf("could not send message: %w", err))
		}
	}
}
