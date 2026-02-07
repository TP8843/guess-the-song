package commands

import (
	"guess-the-song-discord/internal"

	"github.com/bwmarrin/discordgo"
)

var (
	UnlinkUserCommand = discordgo.ApplicationCommand{
		Name:        "unlink",
		Description: "Unlink your discord account from your last.fm username",
		Type:        discordgo.ChatApplicationCommand,
		Options:     []*discordgo.ApplicationCommandOption{},
	}
)

func (ctx *Context) UnlinkUser(s *discordgo.Session, i *discordgo.InteractionCreate) {
	discord := i.Member.User.ID

	err := ctx.db.UnlinkUser(discord)
	if err != nil {
		internal.CommandErrorResponse(s, i, "Error unlinking from your last.fm account")
		return
	}

	internal.CommandSuccessResponse(s, i, "Successfully unlinked your last.fm account")
}
