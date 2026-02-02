package main

import (
	"fmt"
	"log"

	"guess-the-song-discord/internal/commands"

	"github.com/bwmarrin/discordgo"
)

var (
	commandList = []*discordgo.ApplicationCommand{
		&commands.GuessTheSongCommand,
		&commands.EndGameCommand,
	}
)

var registeredCommands []*discordgo.ApplicationCommand

var commandHandlers = map[string]func(s *discordgo.Session, i *discordgo.InteractionCreate){}

func initCommandListener(quizContext *commands.Context) {
	commandHandlers["guess-the-song"] = quizContext.GuessTheSong
	commandHandlers["end-game"] = quizContext.EndGame

	registeredCommands = make([]*discordgo.ApplicationCommand, len(commandList))

	s.AddHandler(func(s *discordgo.Session, i *discordgo.InteractionCreate) {
		if h, ok := commandHandlers[i.ApplicationCommandData().Name]; ok {
			h(s, i)
		}
	})
}

func registerCommands() {
	fmt.Println("Registering commands...")

	for i, command := range commandList {
		cmd, err := s.ApplicationCommandCreate(s.State.User.ID, *GuildID, command)
		if err != nil {
			log.Panicf("Failed to create %v command: %v", command.Name, err)
		}
		registeredCommands[i] = cmd
	}
}

func unregisterCommands() {
	fmt.Println("Unregistering commands...")

	for _, command := range registeredCommands {
		err := s.ApplicationCommandDelete(s.State.User.ID, *GuildID, command.ID)
		if err != nil {
			log.Panicf("Failed to delete %v command: %v", command.Name, err)
		}
	}
}
