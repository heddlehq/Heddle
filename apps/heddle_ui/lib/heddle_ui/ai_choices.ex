defmodule HeddleUI.AIChoices do
  @moduledoc """
  What the screens offer for an AI task: the models that can do it, what runs when
  nothing is picked, and what's wrong with the current choice.
  """

  use Gettext, backend: HeddleUI.Gettext

  alias HeddleAI.AI
  alias HeddleAI.Models
  alias HeddleNodes.Services.AI, as: NodeAI

  @doc """
  Returns the choice for a node with these values, where blanks fall to the AI page.
  """
  def model_choice(fields, capability) do
    value = fields["model"] || ""
    blank = Map.put(fields, "model", "")

    blank |> NodeAI.resolve(capability) |> choice(value, capability)
  end

  @doc """
  Returns the choice for a row of the AI page, which is what the blanks fall to.
  """
  def default_choice(credential, value, capability) do
    resolved =
      case credential do
        "" -> {:ok, [credential: nil, model: nil]}
        name -> NodeAI.resolve(%{"credential" => name, "model" => ""}, capability)
      end

    choice(resolved, value, capability)
  end

  @doc """
  Says what a node with no credential uses.
  """
  def credential_default(capability) do
    case {NodeAI.default_credential_name(capability), AI.target(credential: nil)} do
      {nil, {:ok, _provider, _configured}} -> gettext("Default: this instance's LLM")
      {nil, {:error, _message}} -> gettext("Default: none set up")
      {name, _target} -> gettext("Default: %{name}", name: name)
    end
  end

  defp choice({:error, _message}, value, _capability) do
    failed(value, gettext("This credential doesn't exist anymore. Pick another one."))
  end

  defp choice({:ok, resolved}, value, capability) do
    case AI.target(resolved) do
      {:ok, provider, configured} ->
        models = Models.options(provider, capability)
        default = default_model(resolved[:model], provider, configured, capability)

        %{
          options: options(models, value),
          value: value,
          default: default && Models.label(provider, default),
          problem: problem(provider, capability, value, default, configured, models)
        }

      {:error, _message} ->
        failed(value, gettext("No AI provider is set up yet."))
    end
  end

  defp failed(value, problem) do
    %{options: options([], value), value: value, default: nil, problem: problem}
  end

  defp options(models, value) do
    listed = Enum.map(models, &{&1.label, &1.id})

    if value == "" or Enum.any?(models, &(&1.id == value)) do
      listed
    else
      [{gettext("%{model} (not available)", model: value), value} | listed]
    end
  end

  defp default_model(picked, _provider, _configured, _capability) when is_binary(picked) do
    picked
  end

  defp default_model(nil, provider, configured, :vision) do
    Models.default(provider, :vision) || configured
  end

  defp default_model(nil, provider, configured, :text) do
    configured || Models.default(provider, :text)
  end

  defp default_model(nil, provider, _configured, capability) do
    Models.default(provider, capability)
  end

  defp problem(provider, capability, value, default, configured, models) do
    label = Models.provider_label(provider)

    cond do
      is_nil(default) or (models == [] and capability not in [:text, :vision]) ->
        gettext("%{provider} can't do this here. Use a credential from another provider.",
          provider: label
        )

      value != "" and Models.check(provider, capability, value, configured) != :ok ->
        gettext("%{model} isn't available on %{provider}. Pick one from the list.",
          model: value,
          provider: label
        )

      true ->
        nil
    end
  end
end
