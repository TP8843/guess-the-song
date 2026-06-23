defmodule GuessTheSong.Release do
  @app :guess_the_song

  def migrate do
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end

  def rollback(repo, version) do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.run(repo, :down, to: version)
      end)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
end
