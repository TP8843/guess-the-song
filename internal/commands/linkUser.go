package commands

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal"
	"log"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

type LinkUserOptions struct {
	LastFm string
}

var (
	LinkUserCommand = discordgo.ApplicationCommand{
		Name:        "link",
		Description: "Link your discord account to your last.fm username",
		Type:        discordgo.ChatApplicationCommand,
		Options: []*discordgo.ApplicationCommandOption{
			{
				Name:        "last-fm",
				Description: "last.fm username",
				Type:        discordgo.ApplicationCommandOptionString,
				Required:    true,
			},
		},
	}
)

// parseLinkUserOptions Puts all data passed in through options into a struct
func parseLinkUserOptions(options []*discordgo.ApplicationCommandInteractionDataOption) (out *LinkUserOptions, err error) {
	const usernameOptKey = "last-fm"

	optionMap := make(map[string]*discordgo.ApplicationCommandInteractionDataOption, len(options))
	for _, option := range options {
		optionMap[option.Name] = option
	}

	username, ok := optionMap[usernameOptKey]
	if !ok {
		return nil, errors.New("could not find input last.fm username")
	}

	return &LinkUserOptions{LastFm: username.StringValue()}, nil
}

func (ctx *Context) LinkUser(s *discordgo.Session, i *discordgo.InteractionCreate) {
	discord := i.Member.User.ID

	options, err := parseLinkUserOptions(i.ApplicationCommandData().Options)

	if err != nil {
		internal.CommandErrorResponse(s, i, "No last.fm username input")
		return
	}

	err = ctx.db.LinkUser(discord, options.LastFm)
	if err != nil {
		log.Println(err)
		internal.CommandErrorResponse(s, i, "Error linking to your last.fm account")
		return
	}

	// Get user info
	info, err := ctx.Lm.User.GetInfo(lastfm.P{
		"user": options.LastFm,
	})
	if err != nil {
		log.Println(err)
		internal.CommandErrorResponse(s, i, "Could not find your last.fm account")
	}

	fmt.Printf("%d", len(info.Images))
	err = s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
		Type: discordgo.InteractionResponseChannelMessageWithSource,
		Data: &discordgo.InteractionResponseData{
			Embeds: []*discordgo.MessageEmbed{
				{
					Title: fmt.Sprintf("Linked your last.fm account: %s", options.LastFm),
					Color: 0x00FF00,
					Image: &discordgo.MessageEmbedImage{
						URL: info.Images[2].Url,
					},
					Description: info.Url,
				},
			},
		},
	})

	if err != nil {
		log.Println(err)
	}
}
