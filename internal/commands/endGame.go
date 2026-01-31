package commands

import (
	"fmt"
	"guess-the-song-discord/internal"
	"log"

	"github.com/bwmarrin/discordgo"
)

var (
	EndGameCommand = discordgo.ApplicationCommand{
		Name:        "end-game",
		Description: "End the currently running game",
		Type:        discordgo.ChatApplicationCommand,
	}
)

// EndGame End the game currently running in the server
func (ctx *Context) EndGame(s *discordgo.Session, i *discordgo.InteractionCreate) {
	if !ctx.quizState.HasQuiz(i.GuildID) {
		internal.CommandErrorResponse(s, i, "No quiz currently running in server.")
		return
	}

	quiz, err := ctx.quizState.GetQuiz(i.GuildID)
	if err != nil {
		log.Println(fmt.Errorf("could not get quiz: %w", err))
		return
	}

	quiz.EndGame()

	err = s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
		Type: discordgo.InteractionResponseChannelMessageWithSource,
		Data: &discordgo.InteractionResponseData{
			Content: "Ending current game",
		},
	})
}
