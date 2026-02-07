package commands

import (
	"fmt"
	"guess-the-song-discord/internal"
	"guess-the-song-discord/internal/state/tracks"
	"log"
	"strings"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

type GuessTheSongOptions struct {
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
	GuessTheSongCommand = discordgo.ApplicationCommand{
		Name:        "guess-the-song",
		Description: "Starts a state using the top tracks of each user through Last.fm",
		Type:        discordgo.ChatApplicationCommand,
		Options: []*discordgo.ApplicationCommandOption{
			{
				Name:        "users",
				Description: "Space separated list of users to take part in state",
				Type:        discordgo.ApplicationCommandOptionString,
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
				Description: "Period to take tracks from (default: overall)",
				Type:        discordgo.ApplicationCommandOptionString,
				Choices: []*discordgo.ApplicationCommandOptionChoice{
					{
						Name:  "overall",
						Value: "overall",
					},
					{
						Name:  "week",
						Value: "7days",
					},
					{
						Name:  "month",
						Value: "1month",
					},
					{
						Name:  "3 months",
						Value: "3month",
					},
					{
						Name:  "6 months",
						Value: "6month",
					},
					{
						Name:  "year",
						Value: "12month",
					},
				},
			},
		},
	}
)

// parseGuessTheSongOptions Puts all data passed in through options into a struct
func parseGuessTheSongOptions(options []*discordgo.ApplicationCommandInteractionDataOption) (out *GuessTheSongOptions, err error) {
	const (
		usersOptKey         = "users"
		periodOptKey        = "period"
		tracksPerUserOptKey = "tracks-per-user"
		roundsOptKey        = "rounds"
	)

	// Default options
	out = &GuessTheSongOptions{
		Users:         nil,
		Period:        "overall",
		TracksPerUser: 50,
		Rounds:        10,
	}

	optionMap := make(map[string]*discordgo.ApplicationCommandInteractionDataOption, len(options))
	for _, option := range options {
		optionMap[option.Name] = option
	}

	if usersOpt, ok := optionMap[usersOptKey]; ok && usersOpt != nil {
		out.Users = strings.Fields(usersOpt.StringValue())
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

	return out, nil
}

func buildGuessTheSongResponse(options *GuessTheSongOptions, usersSummary string) *discordgo.MessageEmbed {
	description := fmt.Sprintf(
		"Starts a state using the top %d tracks from the past %s using the provided users:",
		options.TracksPerUser, options.Period,
	)

	return &discordgo.MessageEmbed{
		Title:       quizTitle,
		Description: description,
		Fields: []*discordgo.MessageEmbedField{
			{
				Name:  "Users",
				Value: usersSummary,
			},
		},
	}
}

func (ctx *Context) GuessTheSong(s *discordgo.Session, i *discordgo.InteractionCreate) {
	channel, err := internal.FindVoiceChat(s, i.GuildID, i.Member.User.ID)

	if err != nil {
		if err.Error() == "user not in voice channel" {
			internal.CommandErrorResponse(s, i, "You must be inside a voice channel to start a state")
			return
		}

		log.Println(err)
		return
	}

	options, err := parseGuessTheSongOptions(i.ApplicationCommandData().Options)
	if err != nil {
		log.Println(err)
		return
	}

	guild, err := s.State.Guild(i.GuildID)

	if err != nil {
		log.Println(err)
		return
	}

	var members []string
	for _, vs := range guild.VoiceStates {
		if vs.ChannelID == channel {
			if vs.UserID == i.AppID {
				continue
			}
			members = append(members, vs.UserID)
		}
	}

	var users []string

	if len(options.Users) > 0 {
		users = options.Users
	} else {
		users, err = ctx.db.GetUsernames(members)
		if err != nil {
			log.Println(err)
			internal.CommandSuccessResponse(s, i, "Error fetching last.fm usernames")
			return
		}
	}

	err = s.InteractionRespond(i.Interaction, &discordgo.InteractionResponse{
		Type: discordgo.InteractionResponseChannelMessageWithSource,
		Data: &discordgo.InteractionResponseData{
			Content: "Please wait while tracks are fetched from Last.fm",
		},
	})

	if err != nil {
		log.Println(fmt.Errorf("error sending interaction response: %w", err))
		return
	}

	var trackSlice = make([]tracks.LastfmTrack, len(users)*options.TracksPerUser)

	userCountString := ""
	usersSummary := ""
	j := 0
	for _, user := range users {
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

		for k, track := range userTracks.Tracks {
			trackSlice[j*options.TracksPerUser+k] = tracks.LastfmTrack{
				LastfmUrl: track.Url,
				Name:      track.Name,
				Artist:    track.Artist.Name,
				User:      user,
			}
		}
		j += 1

		userCountString = fmt.Sprintf("Fetched %d users...", j)

		_, err = s.InteractionResponseEdit(i.Interaction, &discordgo.WebhookEdit{
			Content: &userCountString,
		})

		if err != nil {
			log.Println(fmt.Errorf("error updating interaction response: %w", err))
			return
		}
	}

	userCountString = "Fetched all users"
	_, err = s.InteractionResponseEdit(i.Interaction, &discordgo.WebhookEdit{
		Content: &userCountString,
		Embeds: &[]*discordgo.MessageEmbed{
			buildGuessTheSongResponse(options, usersSummary),
		},
	})

	if err != nil {
		log.Println(fmt.Errorf("error updating interaction response: %w", err))
		return
	}

	if len(trackSlice) == 0 {
		internal.CommandErrorResponse(s, i, "No users found")
		return
	}

	go func() {
		err := ctx.quizState.StartQuiz(i.GuildID, i.ChannelID, channel, trackSlice, options.Rounds)
		if err != nil {
			log.Println(fmt.Errorf("could not start state: %w", err))
		}
	}()
}
