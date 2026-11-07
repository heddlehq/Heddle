defmodule HeddleNodes.Nodes.Slack.UploadFile do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Slack

  definition do
    Slack.definition(
      "Upload File",
      "Sends a file to a channel. The content can come from a Download node.",
      [
        %{type: :text, name: :channel, label: "Channel ID", default: ""},
        %{type: :text, name: :filename, label: "File name", default: ""},
        %{type: :text, name: :content, label: "Content", default: "{{result}}"},
        %{type: :text, name: :comment, label: "Message", default: ""}
      ]
    )
  end

  @impl true
  def handler(context, _input) do
    Slack.run(context, fn token ->
      content = Integration.content(context, "content")
      filename = Integration.field(context, "filename")
      params = [filename: filename, length: byte_size(content)]

      with {:ok, slot} <- Slack.get(token, "files.getUploadURLExternal", params),
           :ok <- Slack.upload(slot["upload_url"], content),
           {:ok, _reply} <-
             Slack.post(token, "files.completeUploadExternal", share(slot, context)) do
        {:ok, %{"file_id" => slot["file_id"]}}
      end
    end)
  end

  defp share(slot, context) do
    %{
      files: [%{id: slot["file_id"], title: Integration.field(context, "filename")}],
      channel_id: Integration.field(context, "channel"),
      initial_comment: Integration.field(context, "comment")
    }
  end
end
