defmodule HeddleCore.Repo.Migrations.AddPreferencesToUsers do
  use Ecto.Migration

  # What a person chose for the interface. Nil means they haven't: the language comes
  # from the browser and the theme stays dark.
  def change do
    alter table(:users) do
      add :locale, :string
      add :theme, :string
    end
  end
end
