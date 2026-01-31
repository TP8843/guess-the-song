package voice

import (
	"context"
	"log"
	"sync"

	"github.com/bwmarrin/discordgo"
)

// Session Contains context for a voice session. Must be created using JoinVoiceSession
type Session struct {
	Vc        *discordgo.VoiceConnection
	pcm       chan []int16
	GuildID   string
	ChannelID string
	Stop      chan bool
	playing   bool
	playingMu sync.Mutex
}

// JoinVoiceSession Joins a voice channel.
// autoDisconnect: if true, disconnects when all members leave the call
func JoinVoiceSession(s *discordgo.Session, guildId, channelId string) (*Session, error) {
	vc, err := s.ChannelVoiceJoin(context.Background(), guildId, channelId, false, true)
	if err != nil {
		log.Println("error joining voice", err)
		return nil, err
	}

	session := &Session{
		Vc:        vc,
		GuildID:   guildId,
		ChannelID: channelId,
		pcm:       make(chan []int16, 10),
		playing:   false,
		playingMu: sync.Mutex{},
		Stop:      make(chan bool, 1),
	}

	// Run automatic packaging of any PCM input to opus and send it
	go session.sendPCM()

	return session, nil
}

// Close Closes a currently running voice session, stopping all playback and closing all processing
func (s *Session) Close() error {
	close(s.pcm)
	return s.Vc.Disconnect(context.Background())
}
