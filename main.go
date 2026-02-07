package main

import (
	"flag"
	"fmt"
	"guess-the-song-discord/internal"
	"guess-the-song-discord/internal/commands"
	"guess-the-song-discord/internal/database"
	"guess-the-song-discord/internal/state"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/bwmarrin/discordgo"
	"github.com/shkh/lastfm-go/lastfm"
)

const (
	EnvBotToken     = "BOT_TOKEN"
	EnvLastFMKey    = "LASTFM_KEY"
	EnvLastFMSecret = "LASTFM_SECRET"
	EnvGuildID      = "GUILD_ID"
	EnvDbPath       = "DB_PATH"
)

var (
	BotToken     = flag.String("token", "", "Bot access token")
	LastFMKey    = flag.String("lastfm_key", "", "LastFM API key")
	LastFMSecret = flag.String("lastfm_secret", "", "LastFM secret")
	GuildID      = flag.String("guild", "", "Guild ID - Empty for all guilds")
	DbPath       = flag.String("db", "", "Path to database file - empty for cwd/database.db")
)

var s *discordgo.Session
var lm *lastfm.Api
var db *database.Connection

func init() {
	flag.Parse()

	internal.SetFromEnv(BotToken, EnvBotToken, "")
	internal.SetFromEnv(LastFMKey, EnvLastFMKey, "")
	internal.SetFromEnv(LastFMSecret, EnvLastFMSecret, "")
	internal.SetFromEnv(GuildID, EnvGuildID, "")
	internal.SetFromEnv(DbPath, EnvDbPath, "./database.db")
}

func init() {
	var err error
	s, err = discordgo.New("Bot " + *BotToken)

	if err != nil {
		fmt.Println("error creating Discord session,", err)
		return
	}

	lm = lastfm.New(*LastFMKey, *LastFMSecret)

	db, err = database.NewConnection(*DbPath)
	if err != nil {
		fmt.Println("error creating database connection,", err)
		return
	}
}

func init() {
	ctx := commands.NewContext(state.NewState(s), lm, db)
	initCommandListener(ctx)
	s.AddHandler(ctx.HandleMessage)
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
