defmodule HeddleNodes.Nodes.Email.List do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.{Email, Imap}

  definition do
    Email.definition(
      "List Emails",
      "Returns the latest emails of a folder through IMAP, newest first, without their content.",
      [
        Email.folder_field(),
        %{type: :text, name: :from, label: "From contains", default: ""},
        %{type: :text, name: :subject, label: "Subject contains", default: ""},
        %{
          type: :select,
          name: :only_unread,
          label: "Which emails",
          options: [%{label: "All", value: "no"}, %{label: "Only unread", value: "yes"}],
          default: "no"
        },
        %{type: :text, name: :limit, label: "How many", default: "20"}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Email.run(context, fn socket ->
      limit = Integration.number(context, "limit", 20)

      with :ok <- Imap.examine(socket, Email.folder(context)),
           {:ok, ids} <- Imap.search(socket, filters(context)),
           {:ok, emails} <- Imap.headers(socket, Enum.take(ids, -limit)) do
        {:ok, Enum.map(emails, &Email.summary/1)}
      end
    end)
  end

  defp filters(context) do
    [
      unread: context["only_unread"] == "yes",
      from: Integration.field(context, "from"),
      subject: Integration.field(context, "subject")
    ]
  end
end
