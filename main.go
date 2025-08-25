package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

var (
	BotToken     = flag.String("token", "", "Bot access token")
	LastFMKey    = flag.String("lastfm_key", "", "LastFM API key")
	LastFMSecret = flag.String("lastfm_secret", "", "LastFM secret")
	GuildID      = flag.String("guild", "", "Guild ID - Empty for all guilds")
)

var s *discordgo.Session

var lm *lastfm.Api

func init() {
	flag.Parse()
}

func init() {
	var err error
	s, err = discordgo.New("Bot " + *BotToken)

	if err != nil {
		fmt.Println("error creating Discord session,", err)
		return
	}

	lm = lastfm.New(*LastFMKey, *LastFMSecret)
}

func init() {
	initCommandListener()
}

func main() {
	s.AddHandler(test)

	s.Identify.Intents = discordgo.IntentsGuildMessages | discordgo.IntentsGuildVoiceStates

	err := s.Open()
	if err != nil {
		fmt.Println("error opening connection,", err)
		return
	}
	defer func(s *discordgo.Session) {
		err := s.Close()
		if err != nil {
			log.Panicln("error closing connection,", err)
		}
	}(s)

	registerCommands()
	defer unregisterCommands()

	fmt.Println("Bot is now running.  Press CTRL-C to exit.")
	sc := make(chan os.Signal, 1)
	signal.Notify(sc, syscall.SIGINT, syscall.SIGTERM, os.Interrupt, os.Kill)
	<-sc

	err = s.Close()

	if err != nil {
		fmt.Println("error closing Discord session,", err)
	}
}

func test(s *discordgo.Session, m *discordgo.MessageCreate) {
	// Ignore all messages created by the bot itself
	if m.Author.ID == s.State.User.ID {
		return
	}

	// If the message is "ping" reply with "Pong!"
	if m.Content == "ping" {
		_, err := s.ChannelMessageSend(m.ChannelID, "Pong!")
		if err != nil {
			fmt.Println("error sending message,", err)
			return
		}
	}

	// If the message is "pong" reply with "Ping!"
	if m.Content == "pong" {
		_, err := s.ChannelMessageSend(m.ChannelID, "Ping!")
		if err != nil {
			fmt.Println("error sending message,", err)
			return
		}
	}
}
