defmodule HeddleNodes.Nodes.Email.Delete do
  use Bobbin.Node

  alias HeddleNodes.Services.{Email, Imap}

  definition do
    Email.definition(
      "Delete Email",
      "Deletes an email for good through IMAP. To keep a copy, use Move Email to the trash folder.",
      [
        Email.id_field(),
        Email.folder_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Email.with_email(context, :select, fn socket, id ->
      with :ok <- Imap.delete(socket, id) do
        {:ok, %{"id" => id}}
      end
    end)
  end
end
