package commands

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal"
	"guess-the-song-discord/internal/quiz"
	"log"
	"strings"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

type TopTrackOptions struct {
	Users  []string
	Period string
}

const (
	TracksPerUser = 3
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

	fields := make([]*discordgo.MessageEmbedField, len(options.Users)*TracksPerUser)

	var tracks = make([]quiz.LastfmTrack, len(options.Users)*TracksPerUser)

	for i, user := range options.Users {
		userTracks, err := context.Lm.User.GetTopTracks(lastfm.P{
			"user":   user,
			"limit":  TracksPerUser,
			"period": options.Period,
		})
		if err != nil {
			log.Println(err)
			fields[i] = &discordgo.MessageEmbedField{
				Name:  user,
				Value: "Could not find top tracks for user",
			}
			continue
		}

		for j, track := range userTracks.Tracks {
			tracks[i*TracksPerUser+j] = quiz.LastfmTrack{
				LastfmUrl: track.Url,
				Name:      track.Name,
				Artist:    track.Artist.Name,
				User:      user,
			}

			fields[i*TracksPerUser+j] = &discordgo.MessageEmbedField{
				Name: tracks[i*TracksPerUser+j].User,
				Value: fmt.Sprintf("%s - %s (%s)",
					tracks[i*TracksPerUser+j].Name,
					tracks[i*TracksPerUser+j].Artist,
					tracks[i*TracksPerUser+j].LastfmUrl),
			}
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
						"- Voice Channel: %s", options.Period, i.ChannelID, channel),
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

//// Test connecting and disconnecting from vc
//session, err := voice.JoinVoiceSession(s, i.GuildID, channel)
//if err != nil {
//	log.Println(err)
//	return
//}
//
//time.Sleep(1000 * time.Millisecond)
//
//err = session.PlayFile(testPreview)
//if err != nil {
//	log.Println(fmt.Errorf("error playing file, %v", err))
//}
//
//err = session.Close()
//if err != nil {
//	log.Println(err)
//	return
//}

//deezerResponse, err := deezer.Search(userTracks.Tracks[0].Name, userTracks.Tracks[0].Artist.Name)
//var deezerPreview string
//if err != nil {
//	log.Println(err)
//} else {
//	deezerPreview = deezerResponse.Preview
//	if testPreview == "" {
//		testPreview = deezerPreview
//	}
//}
