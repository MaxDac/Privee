defmodule BautaWeb.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :bauta_web

  def migrate do
    load_app()

    for repo <- repos() do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
        {:ok, _, _} -> :ok
        {:error, reason} -> raise "migration failed for #{inspect(repo)}: #{inspect(reason)}"
      end
    end
  end

  def rollback(repo, version) do
    load_app()

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
      {:ok, _, _} ->
        :ok

      {:error, reason} ->
        raise "rollback failed for #{inspect(repo)} to #{version}: #{inspect(reason)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
