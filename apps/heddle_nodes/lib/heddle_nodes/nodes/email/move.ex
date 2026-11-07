defmodule HeddleNodes.Nodes.Email.Move do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.{Email, Imap}

  definition do
    Email.definition(
      "Move Email",
      "Moves an email to another folder through IMAP. Its ID changes there.",
      [
        Email.id_field(),
        Email.folder_field(),
        %{type: :text, name: :target_folder, label: "Target folder", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Email.with_email(context, :select, fn socket, id ->
      target = Integration.field(context, "target_folder")

      with :ok <- Imap.move(socket, id, target) do
        {:ok, %{"id" => id, "folder" => target}}
      end
    end)
  end
end
