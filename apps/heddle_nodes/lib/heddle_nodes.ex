defmodule HeddleNodes do
  @moduledoc """
  Bobbin manifest for the built-in Heddle nodes.
  """

  use Bobbin.Manifest

  alias HeddleNodes.Nodes.{
    AI,
    AIAgent,
    Approval,
    Condition,
    Csv,
    ErrorTrigger,
    Eval,
    ForEach,
    FormTrigger,
    HttpRequest,
    Logger,
    Merge,
    Output,
    RespondToWebhook,
    Schedule,
    Spool,
    Start,
    Subflow,
    SubflowTrigger,
    Switch,
    Validate,
    Variable,
    Wait,
    Webhook
  }

  manifest do
    nodes([
      Start,
      Webhook,
      FormTrigger,
      Schedule,
      ErrorTrigger,
      SubflowTrigger,
      Variable,
      Validate,
      Eval,
      Csv.Read,
      Csv.Write,
      HttpRequest,
      Spool.FindRows,
      Spool.InsertRows,
      Spool.UpdateRows,
      Spool.UpsertRows,
      Spool.DeleteRows,
      AIAgent,
      AI.GenerateImage,
      AI.EditImage,
      AI.DescribeImage,
      AI.TranscribeAudio,
      AI.TextToSpeech,
      AI.Summarize,
      AI.Translate,
      AI.Classify,
      AI.ExtractData,
      Condition,
      Switch,
      ForEach,
      Merge,
      Wait,
      Approval,
      Subflow,
      Logger,
      Output,
      RespondToWebhook
    ])
  end
end
