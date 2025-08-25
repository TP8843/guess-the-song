package main

import (
	"fmt"
	"log"

	"guess-the-song-discord/internal/parsing"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

var (
	commands = []*discordgo.ApplicationCommand{
		{
			Name:        "top-tracks",
			Description: "Starts a quiz using the top tracks of each user through Last.fm",
			Type:        discordgo.ChatApplicationCommand,
			Options: []*discordgo.ApplicationCommandOption{
				{
					Name:        "users",
					Description: "Space separated list of users to take part in quiz",
					Type:        discordgo.ApplicationCommandOptionString,
					Required:    true,
				},
				{
					Name:        "period",
					Description: "Period to take top tracks from (default: overall)",
					Type:        discordgo.ApplicationCommandOptionString,
					Choices: []*discordgo.ApplicationCommandOptionChoice{
						{
							Name:  "overall",
							Value: "overall",
						},
						{
							Name:  "Week",
							Value: "7days",
						},
						{
							Name:  "Month",
							Value: "1month",
						},
						{
							Name:  "3 Months",
							Value: "3month",
						},
						{
							Name:  "6 Months",
							Value: "6month",
						},
						{
							Name:  "Year",
							Value: "12month",
						},
					},
				},
			},
		},
	}
)

var registeredCommands = make([]*discordgo.ApplicationCommand, len(commands))

var commandHandlers = map[string]func(s *discordgo.Session, i *discordgo.InteractionCreate){
	"top-tracks": topTracks,
}

func topTracks(s *discordgo.Session, i *discordgo.InteractionCreate) {
	guild, err := s.State.Guild(i.GuildID)

	if err != nil {
		log.Println(err)
		return
	}

	// Current voice channel for user
	var channel string

	for _, vs := range guild.VoiceStates {
		if vs.UserID == i.Member.User.ID {
			channel = vs.ChannelID
		}
	}

	if channel == "" {
		err := s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
			Type: discordgo.InteractionResponseChannelMessageWithSource,
			Data: &discordgo.InteractionResponseData{
				Content: "Must be in a voice channel to start quiz",
			},
		})

		if err != nil {
			log.Panicln(err.Error())
		}

		return
	}

	options := i.ApplicationCommandData().Options

	users, period, err := parsing.ParseTopTrackOptions(options)

	if err != nil && err.Error() == "no users" {
		err := s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
			Type: discordgo.InteractionResponseChannelMessageWithSource,
			Data: &discordgo.InteractionResponseData{
				Content: "Users are required",
			},
		})

		if err != nil {
			log.Panicln(err.Error())
		}

		return
	}

	fields := make([]*discordgo.MessageEmbedField, len(users))

	for i, user := range users {
		tracks, err := lm.User.GetTopTracks(lastfm.P{
			"user":   user,
			"limit":  3,
			"period": period,
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
			Value: fmt.Sprintf("%s - %s, %s - %s, %s - %s, ...",
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
						"- period %s\n"+
						"- channel ID %s", period, i.ChannelID),
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

	for i, command := range commands {
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
