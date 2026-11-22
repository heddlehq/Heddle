defmodule HeddleNodes.ManifestsTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Manifests

  test "turns each action of a manifest into a node module" do
    assert Manifests.modules("slack") == [
             Manifests.Slack.SendMessage,
             Manifests.Slack.ReadMessages,
             Manifests.Slack.UpdateMessage,
             Manifests.Slack.DeleteMessage,
             Manifests.Slack.AddReaction,
             Manifests.Slack.ListChannels
           ]

    definition = Manifests.Slack.ListChannels.definition()

    assert definition.name == "Slack: List Channels"
    assert definition.category == :slack
    assert definition.icon == "logo-slack"
    assert definition.outputs == ["success", "error"]

    assert [
             %{type: :credential, kind: "slack"},
             %{type: :select, name: :types, default: "public_channel", options: [_, _, _]}
           ] = definition.ui_fields
  end

  test "a number field shows as text, with its default" do
    fields = Manifests.Slack.ReadMessages.definition().ui_fields

    assert %{type: :text, default: "20"} = Enum.find(fields, &(&1[:name] == :limit))
  end

  test "declares the credential kinds of its manifests" do
    assert [%{id: "slack", label: "Slack", fields: [%{name: "token", secret: true}]}] =
             Manifests.credential_kinds()
  end
end
