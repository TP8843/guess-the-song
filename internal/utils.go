package internal

import (
	"errors"
	"log"

	"github.com/bwmarrin/discordgo"
)

func CommandErrorResponse(s *discordgo.Session, i *discordgo.InteractionCreate, message string) {
	err := s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
		Type: discordgo.InteractionResponseChannelMessageWithSource,
		Data: &discordgo.InteractionResponseData{
			Embeds: []*discordgo.MessageEmbed{
				{
					Title:       "Something went wrong :(",
					Description: message,
				},
			},
		},
	})

	if err != nil {
		log.Println(err)
	}
}

func FindVoiceChat(s *discordgo.Session, guildId string, userId string) (channel *string, err error) {
	guild, err := s.State.Guild(guildId)

	if err != nil {
		log.Println(err)
		return nil, errors.New("no guild found")
	}

	for _, vs := range guild.VoiceStates {
		if vs.UserID == userId {
			channel = &vs.ChannelID
		}
	}

	if channel == nil {
		return nil, errors.New("user not in voice channel")
	}

	return channel, nil
}
