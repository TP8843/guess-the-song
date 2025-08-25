package commands

import (
	"errors"
	"strings"

	"github.com/bwmarrin/discordgo"
)

type TopTrackOptions struct {
	Users  []string
	Period string
}

var (
	TopTrackCommand = discordgo.ApplicationCommand{
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
	}
)

// ParseTopTrackOptions Puts all data passed in through options into a struct
func ParseTopTrackOptions(options []*discordgo.ApplicationCommandInteractionDataOption) (out *TopTrackOptions, err error) {
	out = &TopTrackOptions{nil, "overall"}

	optionMap := make(map[string]*discordgo.ApplicationCommandInteractionDataOption, len(options))
	for _, option := range options {
		optionMap[option.Name] = option
	}

	if optionMap["users"] == nil {
		return nil, errors.New("missing users")
	}

	if optionMap["period"] != nil {
		out.Period = optionMap["period"].StringValue()
	}

	out.Users = strings.Split(optionMap["users"].StringValue(), " ")

	return out, nil
}
