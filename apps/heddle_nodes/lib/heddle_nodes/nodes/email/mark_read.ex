defmodule HeddleNodes.Nodes.Email.MarkRead do
  use Bobbin.Node

  alias HeddleNodes.Services.{Email, Imap}

  definition do
    Email.definition(
      "Mark as Read",
      "Marks an email as read through IMAP.",
      [
        Email.id_field(),
        Email.folder_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Email.with_email(context, :select, fn socket, id ->
      with :ok <- Imap.add_flag(socket, id, "\\Seen") do
        {:ok, %{"id" => id}}
      end
    end)
  end
end
