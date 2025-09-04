package commands

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal"
	"guess-the-song-discord/internal/quiz/tracks"
	"log"
	"strings"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

type TopTrackOptions struct {
	Users         []string
	Period        string
	TracksPerUser int
	Rounds        int
}

const quizTitle = "Guess the Song - Top Tracks"

var (
	MinTracksPerUser = 1.0
	MaxTracksPerUser = 100.0
	MinRounds        = 1.0
	MaxRounds        = 30.0
)

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
				Name:        "tracks-per-user",
				Description: "Maximum number of tracks to pull per user",
				Type:        discordgo.ApplicationCommandOptionInteger,
				MinValue:    &MinTracksPerUser,
				MaxValue:    MaxTracksPerUser,
			},
			{
				Name:        "rounds",
				Description: "Rounds for game (if there are enough tracks)",
				Type:        discordgo.ApplicationCommandOptionInteger,
				MinValue:    &MinRounds,
				MaxValue:    MaxRounds,
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

// parseTopTrackOptions Puts all data passed in through options into a struct
func parseTopTrackOptions(options []*discordgo.ApplicationCommandInteractionDataOption) (out *TopTrackOptions, err error) {
	const (
		usersOptKey         = "users"
		periodOptKey        = "period"
		tracksPerUserOptKey = "tracks-per-user"
		roundsOptKey        = "rounds"
	)

	out = &TopTrackOptions{nil, "overall", 50, 10}

	optionMap := make(map[string]*discordgo.ApplicationCommandInteractionDataOption, len(options))
	for _, option := range options {
		optionMap[option.Name] = option
	}

	usersOpt, ok := optionMap[usersOptKey]
	if !ok || usersOpt == nil || usersOpt.StringValue() == "" {
		return nil, errors.New("no users")
	}

	if periodOpt, ok := optionMap[periodOptKey]; ok && periodOpt != nil {
		out.Period = periodOpt.StringValue()
	}

	if tpuOpt, ok := optionMap[tracksPerUserOptKey]; ok && tpuOpt != nil {
		out.TracksPerUser = int(tpuOpt.IntValue())
	}

	if roundsOpt, ok := optionMap[roundsOptKey]; ok && roundsOpt != nil {
		out.Rounds = int(roundsOpt.IntValue())
	}

	out.Users = strings.Fields(usersOpt.StringValue())

	return out, nil
}

func buildTopTracksStartResponseData(options *TopTrackOptions, usersSummary string) *discordgo.InteractionResponseData {
	description := fmt.Sprintf(
		"Starts a quiz using the top %d tracks from the past %s using the provided users:",
		options.TracksPerUser, options.Period,
	)

	return &discordgo.InteractionResponseData{
		Embeds: []*discordgo.MessageEmbed{
			{
				Title:       quizTitle,
				Description: description,
				Fields: []*discordgo.MessageEmbedField{
					{
						Name:  "Users",
						Value: usersSummary,
					},
				},
			},
		},
	}
}

func (ctx *Context) TopTracks(s *discordgo.Session, i *discordgo.InteractionCreate) {
	channel, err := internal.FindVoiceChat(s, i.GuildID, i.Member.User.ID)

	if err != nil {
		if err.Error() == "user not in voice channel" {
			internal.CommandErrorResponse(s, i, "You must be inside a voice channel to start a quiz")
			return
		}

		log.Println(err)
		return
	}

	options, err := parseTopTrackOptions(i.ApplicationCommandData().Options)

	if err != nil {
		if err.Error() == "no users" {
			internal.CommandErrorResponse(s, i, "You must enter space separated Last.fm usernames to use for the quiz")
		}

		log.Println(err)
		return
	}

	var trackSlice = make([]tracks.LastfmTrack, len(options.Users)*options.TracksPerUser)

	usersSummary := ""

	for i, user := range options.Users {
		userTracks, err := ctx.Lm.User.GetTopTracks(lastfm.P{
			"user":   user,
			"limit":  options.TracksPerUser,
			"period": options.Period,
		})
		if err != nil {
			log.Println(err)
			usersSummary += fmt.Sprintf("- %s - not found\n", user)
			continue
		}

		usersSummary += fmt.Sprintf("- %s - %d tracks\n", user, len(userTracks.Tracks))

		for j, track := range userTracks.Tracks {
			trackSlice[i*options.TracksPerUser+j] = tracks.LastfmTrack{
				LastfmUrl: track.Url,
				Name:      track.Name,
				Artist:    track.Artist.Name,
				User:      user,
			}
		}
	}

	err = s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
		Type: discordgo.InteractionResponseChannelMessageWithSource,
		Data: buildTopTracksStartResponseData(options, usersSummary),
	})

	if err != nil {
		log.Println(err)
		return
	}

	go func() {
		err := ctx.quizState.StartQuiz(i.GuildID, i.ChannelID, channel, trackSlice, options.Rounds)
		if err != nil {
			log.Println(fmt.Errorf("could not start quiz: %w", err))
		}
	}()
}
