package main

import (
	"flag"
	"fmt"
	"guess-the-song-discord/internal/commands"
	"guess-the-song-discord/internal/quiz"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

// For managing current games: https://github.com/patrickmn/go-cache

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
	commandContext := commands.NewContext(quiz.NewState(s), lm)
	initCommandListener(commandContext)
	s.AddHandler(commandContext.HandleMessage)
}

func main() {
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
