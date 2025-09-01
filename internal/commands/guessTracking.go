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

	// Only read messages from the channel where the quiz was started
	if quiz.TextChannel != i.ChannelID {
		return
	}

	result := quiz.ProcessGuess(i.Author.ID, i.Content)

	if result != nil {
		var plural rune = 's'

		if result.Points == 1 {
			plural = '\000'
		}

		_, err := s.ChannelMessageSendEmbedReply(i.ChannelID, &discordgo.MessageEmbed{
			Fields: []*discordgo.MessageEmbedField{
				{
					Value: fmt.Sprintf("Correct! %s is %s (+%d point%c)",
						result.Type,
						result.Value,
						result.Points,
						plural,
					),
				},
			},
		}, i.SoftReference())
		if err != nil {
			log.Println(fmt.Errorf("could not send message: %w", err))
		}
	}
}
