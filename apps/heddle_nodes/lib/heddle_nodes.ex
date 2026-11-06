defmodule HeddleNodes do
  @moduledoc """
  Bobbin manifest for the built-in Heddle nodes.
  """

  use Bobbin.Manifest

  alias HeddleNodes.Nodes.{
    AIAgent,
    Condition,
    Csv,
    Email,
    Eval,
    ForEach,
    Ftp,
    HttpRequest,
    Logger,
    Output,
    RespondToWebhook,
    S3,
    Schedule,
    Slack,
    Start,
    Variable,
    Webhook
  }

  manifest do
    nodes([
      Start,
      Webhook,
      Schedule,
      Variable,
      Eval,
      Csv,
      HttpRequest,
      Slack,
      Email,
      S3,
      Ftp,
      AIAgent,
      Condition,
      ForEach,
      Logger,
      Output,
      RespondToWebhook
    ])
  end
end
