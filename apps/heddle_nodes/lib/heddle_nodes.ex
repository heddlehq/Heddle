defmodule HeddleNodes do
  @moduledoc """
  FusionKit manifest for the built-in Heddle nodes.
  """

  use FusionKit.Manifest

  alias HeddleNodes.Nodes.{
    Condition,
    Eval,
    HttpRequest,
    Logger,
    Output,
    Start,
    Variable,
    Webhook
  }

  manifest do
    nodes([
      Start,
      Webhook,
      Variable,
      Eval,
      HttpRequest,
      Condition,
      Logger,
      Output
    ])
  end
end
