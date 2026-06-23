defmodule GuessTheSong.DB.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:discord_id, :integer)
    field(:lastfm_username, :string)
  end

  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:discord_id, :lastfm_username])
    |> validate_required([:discord_id, :lastfm_username])
    |> unique_constraint(:discord_id)
  end
end
