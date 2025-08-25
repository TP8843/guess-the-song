package main

import (
	"fmt"
	"guess-the-song-discord/internal"
	"log"

	"guess-the-song-discord/internal/commands"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

var (
	commandList = []*discordgo.ApplicationCommand{
		&commands.TopTrackCommand,
	}
)

var registeredCommands = make([]*discordgo.ApplicationCommand, len(commandList))

var commandHandlers = map[string]func(s *discordgo.Session, i *discordgo.InteractionCreate){
	"top-tracks": topTracks,
}

func topTracks(s *discordgo.Session, i *discordgo.InteractionCreate) {
	channel, err := internal.FindVoiceChat(s, i.GuildID, i.Member.User.ID)

	if err != nil {
		if err.Error() == "user not in voice channel" {
			internal.CommandErrorResponse(s, i, "You must be inside a voice channel to start a quiz")
			return
		}

		log.Println(err)
		return
	}

	options, err := commands.ParseTopTrackOptions(i.ApplicationCommandData().Options)

	if err != nil {
		if err.Error() == "no users" {
			internal.CommandErrorResponse(s, i, "You must enter space separated Last.fm usernames to use for the quiz")
		}

		log.Println(err)
		return
	}

	fields := make([]*discordgo.MessageEmbedField, len(options.Users))

	for i, user := range options.Users {
		tracks, err := lm.User.GetTopTracks(lastfm.P{
			"user":   user,
			"limit":  3,
			"period": options.Period,
		})
		if err != nil {
			log.Println(err)
			fields[i] = &discordgo.MessageEmbedField{
				Name:  user,
				Value: "Could not find tracks for user",
			}
			continue
		}

		fields[i] = &discordgo.MessageEmbedField{
			Name: user,
			Value: fmt.Sprintf("1. %s - %s,\n 2. %s - %s,\n 3. %s - %s,\n 4. ...",
				tracks.Tracks[0].Name,
				tracks.Tracks[0].Artist.Name,
				tracks.Tracks[1].Name,
				tracks.Tracks[1].Artist.Name,
				tracks.Tracks[2].Name,
				tracks.Tracks[2].Artist.Name,
			),
		}
	}

	err = s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
		Type: discordgo.InteractionResponseChannelMessageWithSource,
		Data: &discordgo.InteractionResponseData{
			Embeds: []*discordgo.MessageEmbed{
				{
					Title: "Top Tracks Quiz",
					Description: fmt.Sprintf("Starts a top tracks quiz using the provided users with \n"+
						"- Period %s\n"+
						"- Text Channel %s\n"+
						"- Voice Channel: %s", options.Period, i.ChannelID, *channel),
					Fields: fields,
				},
			},
		},
	})

	if err != nil {
		log.Println(err)
		return
	}
}

func initCommandListener() {
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
