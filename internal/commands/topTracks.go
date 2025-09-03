package commands

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal"
	"guess-the-song-discord/internal/quiz/tracks"
	"log"
	"strconv"
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

// ParseTopTrackOptions Puts all data passed in through options into a struct
func ParseTopTrackOptions(options []*discordgo.ApplicationCommandInteractionDataOption) (out *TopTrackOptions, err error) {
	out = &TopTrackOptions{nil, "overall", 50, 10}

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

	if optionMap["tracks-per-user"] != nil {
		out.TracksPerUser = int(optionMap["tracks-per-user"].IntValue())
	}

	if optionMap["rounds"] != nil {
		out.Rounds = int(optionMap["rounds"].IntValue())
	}

	out.Users = strings.Split(optionMap["users"].StringValue(), " ")

	return out, nil
}

func (context *Context) TopTracks(s *discordgo.Session, i *discordgo.InteractionCreate) {
	channel, err := internal.FindVoiceChat(s, i.GuildID, i.Member.User.ID)

	if err != nil {
		if err.Error() == "user not in voice channel" {
			internal.CommandErrorResponse(s, i, "You must be inside a voice channel to start a quiz")
			return
		}

		log.Println(err)
		return
	}

	options, err := ParseTopTrackOptions(i.ApplicationCommandData().Options)

	if err != nil {
		if err.Error() == "no users" {
			internal.CommandErrorResponse(s, i, "You must enter space separated Last.fm usernames to use for the quiz")
		}

		log.Println(err)
		return
	}

	var trackSlice = make([]tracks.LastfmTrack, len(options.Users)*options.TracksPerUser)

	usersString := ""

	for i, user := range options.Users {
		userTracks, err := context.Lm.User.GetTopTracks(lastfm.P{
			"user":   user,
			"limit":  options.TracksPerUser,
			"period": options.Period,
		})
		if err != nil {
			log.Println(err)
			usersString += fmt.Sprintf("- %s - not found\n", user)
			continue
		}

		usersString += fmt.Sprintf("- %s - %d tracks\n", user, len(userTracks.Tracks))

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
		Data: &discordgo.InteractionResponseData{
			Embeds: []*discordgo.MessageEmbed{
				{
					Title: "Top Tracks Quiz",
					Description: fmt.Sprintf("Starts a top trackSlice quiz using the provided users with \n"+
						"- Period %s\n"+
						"- Text Channel %s\n"+
						"- Voice Channel: %s", options.Period, i.ChannelID, channel),
					Fields: []*discordgo.MessageEmbedField{
						{
							Name:  "Users",
							Value: usersString,
						},
						{
							Name:  "Period",
							Value: options.Period,
						},
						{
							Name:  "Max Tracks Per User",
							Value: strconv.Itoa(options.TracksPerUser),
						},
					},
				},
			},
		},
	})

	if err != nil {
		log.Println(err)
		return
	}

	go func() {
		err := context.quizState.StartQuiz(i.GuildID, i.ChannelID, channel, trackSlice, options.Rounds)
		if err != nil {
			log.Println(fmt.Errorf("could not start quiz: %w", err))
		}
	}()
}
