package voice

import (
	"log"

	"github.com/bwmarrin/discordgo"
)

type Session struct {
	Vc        *discordgo.VoiceConnection
	pcm       chan []int16
	GuildID   string
	ChannelID string
}

// JoinVoiceSession Joins a voice channel.
// autoDisconnect: if true, disconnects when all members leave the call
func JoinVoiceSession(s *discordgo.Session, guildId, channelId string) (*Session, error) {
	vc, err := s.ChannelVoiceJoin(guildId, channelId, false, true)
	if err != nil {
		log.Println("error joining voice", err)
		return nil, err
	}

	session := &Session{
		Vc:        vc,
		GuildID:   guildId,
		ChannelID: channelId,
		pcm:       make(chan []int16, 2),
	}

	// Start automatic packaging of any PCM input to opus and send it
	go session.sendPCM()

	return session, nil
}

func (s *Session) Close() error {
	close(s.pcm)
	return s.Vc.Disconnect()
}
