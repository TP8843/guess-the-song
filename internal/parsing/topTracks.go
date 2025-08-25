package parsing

import (
	"errors"
	"strings"

	"github.com/bwmarrin/discordgo"
)

func ParseTopTrackOptions(options []*discordgo.ApplicationCommandInteractionDataOption) (users []string, period string, err error) {
	optionMap := make(map[string]*discordgo.ApplicationCommandInteractionDataOption, len(options))
	for _, option := range options {
		optionMap[option.Name] = option
	}

	if optionMap["users"] == nil {
		return nil, "overall", errors.New("missing users")
	}

	if optionMap["period"] == nil {
		period = "overall"
	} else {
		period = optionMap["period"].StringValue()
	}

	users = strings.Split(optionMap["users"].StringValue(), " ")

	return users, period, nil
}
