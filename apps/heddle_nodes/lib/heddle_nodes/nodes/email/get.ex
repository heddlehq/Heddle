defmodule HeddleNodes.Nodes.Email.Get do
  use Bobbin.Node

  alias HeddleNodes.Services.{Email, Imap}

  definition do
    Email.definition(
      "Get Email",
      "Returns the text, HTML and attachment names of an email through IMAP, without marking it as read.",
      [
        Email.id_field(),
        Email.folder_field()
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Email.with_email(context, :examine, fn socket, id ->
      with {:ok, email} <- Imap.message(socket, id) do
        {:ok, Email.details(email)}
      end
    end)
  end
end
