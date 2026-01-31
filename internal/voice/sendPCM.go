package voice

import (
	"log"

	"layeh.com/gopus"
)

func (s *Session) sendPCM() {
	if s.pcm == nil {
		return
	}

	encoder, err := gopus.NewEncoder(frameRate, channels, gopus.Audio)
	if err != nil {
		log.Println("error creating opus encoder", err)
		return
	}

	for {
		recv, ok := <-s.pcm
		if !ok {
			log.Println("pcm channel closed")
			return
		}

		opus, err := encoder.Encode(recv, frameSize, maxBytes)
		if err != nil {
			log.Println("error encoding PCM to opus, ", err)
		}

		if s.Vc.Ready == false || s.Vc.OpusSend == nil {
			log.Println("voice channel not ready for opus packets")
			return
		}

		s.Vc.OpusSend <- opus
	}
}
