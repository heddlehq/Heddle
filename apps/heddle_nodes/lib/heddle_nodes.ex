defmodule HeddleNodes do
  @moduledoc """
  Bobbin manifest for the built-in Heddle nodes.
  """

  use Bobbin.Manifest

  alias HeddleNodes.Nodes.{
    AIAgent,
    Condition,
    Eval,
    ForEach,
    HttpRequest,
    Logger,
    Output,
    RespondToWebhook,
    Schedule,
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
      HttpRequest,
      AIAgent,
      Condition,
      ForEach,
      Logger,
      Output,
      RespondToWebhook
    ])
  end
end
