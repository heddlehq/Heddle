defmodule HeddleNodes.Services.Email do
  @moduledoc """
  What the Email nodes that read a mailbox share.
  """

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.{Imap, Mime}

  @service %{title: "Email", category: :email, icon: "hero-envelope-solid"}

  def definition(action, description, fields, credential \\ "imap") do
    @service
    |> Map.put(:credential, credential)
    |> Integration.definition(action, description, fields)
  end

  def folder_field, do: %{type: :text, name: :folder, label: "Folder", default: "INBOX"}
  def id_field, do: %{type: :text, name: :id, label: "Email ID", default: "{{result.id}}"}

  def folder(context) do
    case String.trim(Integration.field(context, "folder")) do
      "" -> "INBOX"
      folder -> folder
    end
  end

  @doc """
  Calls `fun` with a connection to the mailbox.
  """
  def run(context, fun) do
    Integration.run(context, "imap", fn imap -> Imap.session(imap, fun) end)
  end

  @doc """
  Opens the node's folder and calls `fun` with the connection and the email's ID.

  `open` is `:select`, to change the email, or `:examine`, to only read it.
  """
  def with_email(context, open, fun) do
    run(context, fn socket ->
      with {:ok, id} <- id(context),
           :ok <- apply(Imap, open, [socket, folder(context)]),
           :ok <- found(socket, id, context) do
        fun.(socket, id)
      end
    end)
  end

  defp id(context) do
    case context |> Integration.field("id") |> String.trim() |> Integer.parse() do
      {id, ""} when id > 0 -> {:ok, id}
      _other -> {:error, "The Email ID is not valid."}
    end
  end

  # The server says OK to changing an email that isn't there.
  defp found(socket, id, context) do
    case Imap.search(socket, uid: id) do
      {:ok, [^id]} -> :ok
      {:ok, _other} -> {:error, "There is no email #{id} in #{folder(context)}."}
      {:error, _message} = error -> error
    end
  end

  @doc """
  Turns what `Imap.headers/2` returns into what a flow sees.
  """
  def summary(%{uid: uid, flags: flags, raw: raw}) do
    raw |> Mime.parse() |> summary_fields(uid, flags)
  end

  @doc """
  Turns what `Imap.message/2` returns into what a flow sees.

  Attachments are only described, because the content would go into the run's
  context, which is saved as JSON.
  """
  def details(%{uid: uid, flags: flags, raw: raw}) do
    message = Mime.parse(raw)

    message
    |> summary_fields(uid, flags)
    |> Map.merge(%{
      "text" => body(message, "text/plain"),
      "html" => body(message, "text/html"),
      "attachments" => for(%{name: name} = part <- message.parts, name, do: attachment(part))
    })
  end

  defp summary_fields(message, uid, flags) do
    %{
      "id" => uid,
      "from" => Mime.header(message, "from"),
      "to" => Mime.header(message, "to"),
      "cc" => Mime.header(message, "cc"),
      "subject" => Mime.header(message, "subject"),
      "date" => Mime.header(message, "date"),
      "unread" => "\\Seen" not in flags
    }
  end

  defp body(message, type) do
    message.parts
    |> Enum.filter(&(&1.type == type and is_nil(&1.name)))
    |> Enum.map_join("\n", &Mime.text/1)
  end

  defp attachment(part) do
    %{"name" => part.name, "type" => part.type, "size" => byte_size(part.body)}
  end
end
