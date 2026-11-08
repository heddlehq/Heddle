defmodule HeddleNodes.Nodes.FormTrigger do
  @moduledoc """
  Starts a flow when someone sends its form, at a link anyone can open.

  The form is what its controls say (see `Heddle.Form`), and its link and page live
  in heddle_core and heddle_ui: see `HeddleCore.Forms`. A run it starts has what was
  sent in `form`, by field key, and the node passes it on as its `result` too.
  """

  use Bobbin.Node

  definition do
    %{
      name: "Form Trigger",
      title: "Form",
      category: :trigger,
      color: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
      description: "Starts a flow when someone fills in its form, at a link you can share.",
      icon: "hero-clipboard-document-list-solid",
      inputs: [],
      outputs: [:exec],
      show: true,
      ui_fields: [
        %{type: :text, name: :title, label: "Title", default: "Contact us"},
        %{type: :textarea, name: :description, label: "Description", default: ""},
        %{
          type: :form_fields,
          name: :fields,
          label: "Fields",
          default: Heddle.Form.default_json()
        },
        %{type: :text, name: :submit_label, label: "Button", default: "Send"},
        %{
          type: :textarea,
          name: :success_message,
          label: "Message after sending",
          default: "Thank you! We got your answers."
        },
        %{type: :text, name: :redirect_url, label: "Then go to (URL, optional)", default: ""},
        %{
          type: :select,
          name: :accepting,
          label: "Accepting answers",
          options: [%{label: "Yes", value: "yes"}, %{label: "No", value: "no"}],
          default: "yes"
        }
      ]
    }
  end

  @impl true
  def handler(context, _input) do
    {:ok, Map.put(context, "result", context["form"] || %{}), :exec}
  end
end
