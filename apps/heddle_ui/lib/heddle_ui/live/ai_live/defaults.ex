defmodule HeddleUI.AILive.Defaults do
  @moduledoc """
  The part of the AI page that sets what each AI task uses by default.
  """

  use HeddleUI, :html

  alias HeddleUI.AIChoices

  @capabilities [:text, :vision, :image, :transcription, :speech]

  @doc """
  Builds the form from what `HeddleCore.Settings.ai_defaults/0` returns.
  """
  def to_form_params(defaults) do
    for capability <- @capabilities, field <- ["credential", "model"], into: %{} do
      {"#{capability}_#{field}", get_in(defaults, [to_string(capability), field]) || ""}
    end
  end

  @doc """
  Turns what the form sent into what `HeddleCore.Settings.set_ai_defaults/1` takes.
  """
  def to_settings(params) do
    Map.new(@capabilities, fn capability ->
      {to_string(capability),
       %{
         "credential" => params["#{capability}_credential"] || "",
         "model" => params["#{capability}_model"] || ""
       }}
    end)
  end

  @doc """
  Forgets the model of the row whose credential changed, since it belongs to the old one.
  """
  def reset_model(params, ["ai", field]) do
    case String.split(field, "_credential") do
      [capability, ""] -> Map.put(params, "#{capability}_model", "")
      _other -> params
    end
  end

  def reset_model(params, _target), do: params

  attr :form, Phoenix.HTML.Form, required: true
  attr :credentials, :list, required: true

  def defaults_section(assigns) do
    assigns = assign(assigns, :capabilities, @capabilities)

    ~H"""
    <section
      id="ai-defaults"
      class="bg-white dark:bg-slate-900 border border-gray-200 dark:border-slate-800 rounded-xl p-6"
    >
      <h2 class="text-base font-semibold text-gray-900 dark:text-white">
        {gettext("Models")}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {gettext("What each kind of task uses when a node doesn't pick its own.")}
        <.link
          id="ai-credentials-link"
          navigate={~p"/credentials"}
          class="text-primary hover:underline"
        >
          {gettext("Manage credentials")}
        </.link>
      </p>

      <.form
        for={@form}
        id="ai-defaults-form"
        phx-change="change_defaults"
        phx-submit="save_defaults"
        class="mt-6 space-y-6"
      >
        <.task_row
          :for={capability <- @capabilities}
          capability={capability}
          form={@form}
          credentials={@credentials}
        />

        <div class="flex justify-end">
          <.button id="ai-defaults-save" type="submit" variant="primary">
            {gettext("Save")}
          </.button>
        </div>
      </.form>
    </section>
    """
  end

  attr :capability, :atom, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :credentials, :list, required: true

  defp task_row(assigns) do
    credential = assigns.form.params["#{assigns.capability}_credential"] || ""
    text_credential = assigns.form.params["text_credential"] || ""
    model = assigns.form.params["#{assigns.capability}_model"] || ""
    effective = if credential == "", do: text_credential, else: credential

    assigns =
      assign(assigns,
        credential_field: assigns.form[:"#{assigns.capability}_credential"],
        model_field: assigns.form[:"#{assigns.capability}_model"],
        choice: AIChoices.default_choice(effective, model, assigns.capability)
      )

    ~H"""
    <div id={"ai-task-#{@capability}"} class="grid gap-x-4 gap-y-1 md:grid-cols-[2.6fr_3fr_4fr]">
      <div>
        <p class="text-sm font-medium text-gray-900 dark:text-white">{title(@capability)}</p>
        <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">{uses(@capability)}</p>
      </div>
      <.input
        field={@credential_field}
        type="select"
        label={gettext("Credential")}
        options={[{blank_credential(@capability), ""} | @credentials]}
      />
      <.input
        field={@model_field}
        type="select"
        label={gettext("Model")}
        disabled={@choice.options == []}
        options={[{default_label(@choice), ""} | @choice.options]}
      />
      <p
        :if={@choice.problem}
        id={"ai-task-#{@capability}-problem"}
        class="text-xs text-error md:col-span-2 md:col-start-2"
      >
        {@choice.problem}
      </p>
    </div>
    """
  end

  defp default_label(%{default: nil}), do: gettext("Nothing available")
  defp default_label(%{default: model}), do: gettext("Default: %{model}", model: model)

  defp blank_credential(:text), do: gettext("From the environment")
  defp blank_credential(_capability), do: gettext("Same as text")

  defp title(:text), do: gettext("Text and chat")
  defp title(:vision), do: gettext("Reading images")
  defp title(:image), do: gettext("Creating images")
  defp title(:transcription), do: gettext("Transcribing audio")
  defp title(:speech), do: gettext("Text to speech")

  defp uses(:text) do
    gettext("AI Agent, Summarize, Translate, Classify, Extract Data and the flow chats")
  end

  defp uses(:vision), do: gettext("Describe Image")
  defp uses(:image), do: gettext("Generate Image and Edit Image")
  defp uses(:transcription), do: gettext("Transcribe Audio")
  defp uses(:speech), do: gettext("Text to Speech")
end
