defmodule GuessTheSong.DB.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :discord_id, :bigint
      add :lastfm_username, :string
    end

    create unique_index(:users, [:discord_id])
  end
end
