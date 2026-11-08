defmodule HeddleUI.FormHTML do
  @moduledoc """
  The pages of a form: to fill it in, after sending it, closed and missing. See
  `HeddleUI.FormController`.
  """

  use HeddleUI, :html

  @field "w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-[15px] text-gray-900 placeholder-gray-400 shadow-sm transition-all duration-150 hover:border-gray-300 focus:border-primary focus:outline-none focus:ring-4 focus:ring-primary/15 dark:border-slate-700 dark:bg-slate-950 dark:text-gray-100 dark:placeholder-gray-500 dark:hover:border-slate-600"

  attr :page, :map, required: true
  attr :action, :string, required: true
  attr :values, :map, required: true
  attr :errors, :map, required: true
  attr :alert, :string, default: nil
  attr :test, :any, default: nil
  attr :honeypot, :string, required: true
  attr :flash, :map, default: %{}

  def show(assigns) do
    ~H"""
    <.shell test={@test}>
      <div class="space-y-2">
        <h1
          id="form-title"
          class="text-2xl font-semibold tracking-tight text-gray-900 dark:text-white sm:text-3xl"
        >
          {if(@page.title == "", do: gettext("Form"), else: @page.title)}
        </h1>
        <p
          :if={@page.description != ""}
          class="whitespace-pre-line text-[15px] leading-relaxed text-gray-600 dark:text-gray-400"
        >
          {@page.description}
        </p>
      </div>

      <div
        :if={@alert || Phoenix.Flash.get(assigns[:flash] || %{}, :error)}
        id="form-alert"
        role="alert"
        class="mt-6 flex gap-2 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700 dark:border-rose-900/50 dark:bg-rose-900/20 dark:text-rose-300"
      >
        <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
        {@alert || Phoenix.Flash.get(assigns[:flash] || %{}, :error)}
      </div>

      <.form
        for={to_form(@values, as: :form)}
        id="public-form"
        action={@action}
        method="post"
        class="mt-8 space-y-6"
        novalidate={@errors != %{}}
      >
        <div class="hidden" aria-hidden="true">
          <label for="form-website">Website</label>
          <input id="form-website" type="text" name={@honeypot} tabindex="-1" autocomplete="off" />
        </div>

        <div :for={field <- @page.fields} id={"form-field-#{field["key"]}"}>
          <.field field={field} value={@values[field["key"]]} error={@errors[field["key"]]} />
        </div>

        <p :if={@page.fields == []} class="text-sm text-gray-500 dark:text-gray-400">
          {gettext("This form has no fields yet.")}
        </p>

        <button
          id="form-submit"
          type="submit"
          class="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-primary px-5 py-3.5 text-[15px] font-semibold text-primary-content shadow-sm transition-all duration-150 hover:bg-primary/90 hover:shadow-md focus:outline-none focus:ring-4 focus:ring-primary/25 active:scale-[0.99] sm:w-auto"
        >
          {if(@page.submit_label == "", do: gettext("Send"), else: @page.submit_label)}
          <.icon name="hero-arrow-right-mini" class="size-5" />
        </button>
      </.form>
    </.shell>
    """
  end

  attr :field, :map, required: true
  attr :value, :any, default: nil
  attr :error, :atom, default: nil

  defp field(%{field: %{"type" => "checkbox"}} = assigns) do
    ~H"""
    <label for={"form_#{@field["key"]}"} class="group flex cursor-pointer items-start gap-3">
      <input type="hidden" name={"form[#{@field["key"]}]"} value="false" />
      <input
        id={"form_#{@field["key"]}"}
        type="checkbox"
        name={"form[#{@field["key"]}]"}
        value="true"
        checked={@value in [true, "true", "on"]}
        required={@field["required"]}
        class="mt-0.5 size-5 rounded-md border-gray-300 text-primary transition focus:ring-4 focus:ring-primary/15 dark:border-slate-600 dark:bg-slate-950"
      />
      <span class="text-[15px] text-gray-800 dark:text-gray-200">
        {@field["label"]}<.required :if={@field["required"]} />
      </span>
    </label>
    <.field_error error={@error} />
    """
  end

  defp field(assigns) do
    assigns = assign(assigns, :class, @field)

    ~H"""
    <label
      for={"form_#{@field["key"]}"}
      class="mb-2 block text-sm font-medium text-gray-800 dark:text-gray-200"
    >
      {@field["label"]}<.required :if={@field["required"]} />
    </label>
    <%= case @field["type"] do %>
      <% "textarea" -> %>
        <textarea
          id={"form_#{@field["key"]}"}
          name={"form[#{@field["key"]}]"}
          rows="5"
          placeholder={@field["placeholder"]}
          required={@field["required"]}
          maxlength={Heddle.Form.max_length()}
          aria-invalid={@error && "true"}
          class={[@class, @error && error_ring()]}
        >{@value}</textarea>
      <% "select" -> %>
        <div class="relative">
          <select
            id={"form_#{@field["key"]}"}
            name={"form[#{@field["key"]}]"}
            required={@field["required"]}
            aria-invalid={@error && "true"}
            class={[@class, "appearance-none pr-10", @error && error_ring()]}
          >
            <option value="">
              {if(@field["placeholder"] == "", do: gettext("Choose…"), else: @field["placeholder"])}
            </option>
            <option :for={option <- @field["options"]} value={option} selected={option == @value}>
              {option}
            </option>
          </select>
          <.icon
            name="hero-chevron-down"
            class="pointer-events-none absolute right-4 top-1/2 size-4 -translate-y-1/2 text-gray-400"
          />
        </div>
      <% type -> %>
        <input
          id={"form_#{@field["key"]}"}
          type={input_type(type)}
          name={"form[#{@field["key"]}]"}
          value={@value}
          placeholder={@field["placeholder"]}
          required={@field["required"]}
          step={type == "number" && "any"}
          inputmode={type == "number" && "decimal"}
          autocomplete={autocomplete(@field)}
          aria-invalid={@error && "true"}
          class={[@class, @error && error_ring()]}
        />
    <% end %>
    <.field_error error={@error} />
    """
  end

  defp required(assigns) do
    ~H"""
    <span class="ml-0.5 text-primary" aria-hidden="true">*</span>
    """
  end

  attr :error, :atom, default: nil

  defp field_error(assigns) do
    ~H"""
    <p :if={@error} class="mt-1.5 flex items-center gap-1 text-sm text-rose-600 dark:text-rose-400">
      <.icon name="hero-exclamation-circle-mini" class="size-4" /> {error_message(@error)}
    </p>
    """
  end

  defp error_ring,
    do: "border-rose-400 focus:border-rose-500 focus:ring-rose-500/15 dark:border-rose-500/60"

  defp input_type("email"), do: "email"
  defp input_type("number"), do: "number"
  defp input_type("date"), do: "date"
  defp input_type(_type), do: "text"

  defp autocomplete(%{"type" => "email"}), do: "email"
  defp autocomplete(%{"key" => key}) when key in ["name", "nome"], do: "name"
  defp autocomplete(_field), do: "off"

  @doc "What a problem with a field means, for the person filling it in."
  def error_message(:required), do: gettext("Fill in this field.")
  def error_message(:invalid_email), do: gettext("Enter a valid email address.")
  def error_message(:invalid_number), do: gettext("Enter a number.")
  def error_message(:invalid_date), do: gettext("Enter a valid date.")
  def error_message(:invalid_option), do: gettext("Pick one of the options.")
  def error_message(:too_long), do: gettext("This is too long.")
  def error_message(_error), do: gettext("Check this field.")

  attr :page, :map, required: true
  attr :test, :any, default: nil
  attr :execution, :any, default: nil

  def sent(assigns) do
    ~H"""
    <.shell test={@test}>
      <div id="form-sent" class="flex flex-col items-center py-6 text-center">
        <span class="flex size-14 items-center justify-center rounded-full bg-emerald-100 text-emerald-600 dark:bg-emerald-900/30 dark:text-emerald-400">
          <.icon name="hero-check" class="size-7" />
        </span>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight text-gray-900 dark:text-white">
          {gettext("Sent")}
        </h1>
        <p class="mt-2 max-w-md whitespace-pre-line text-[15px] leading-relaxed text-gray-600 dark:text-gray-400">
          {if(@page.success_message == "",
            do: gettext("Thank you! We got your answers."),
            else: @page.success_message
          )}
        </p>
        <.link
          :if={@test && @execution}
          id="form-test-run"
          navigate={~p"/flows/#{@test.id}?execution=#{@execution.public_id}"}
          class="mt-6 inline-flex items-center gap-1.5 rounded-lg bg-primary/10 px-4 py-2 text-sm font-medium text-primary transition-colors hover:bg-primary/20"
        >
          <.icon name="hero-play-circle" class="size-4" /> {gettext("See the run")}
        </.link>
      </div>
    </.shell>
    """
  end

  attr :page, :map, required: true

  def closed(assigns) do
    ~H"""
    <.shell>
      <div id="form-closed" class="flex flex-col items-center py-6 text-center">
        <span class="flex size-14 items-center justify-center rounded-full bg-gray-100 text-gray-500 dark:bg-slate-800 dark:text-gray-400">
          <.icon name="hero-lock-closed" class="size-7" />
        </span>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight text-gray-900 dark:text-white">
          {if(@page.title == "", do: gettext("Form"), else: @page.title)}
        </h1>
        <p class="mt-2 text-[15px] text-gray-600 dark:text-gray-400">
          {gettext("This form isn't taking answers anymore.")}
        </p>
      </div>
    </.shell>
    """
  end

  def not_found(assigns) do
    ~H"""
    <.shell>
      <div id="form-not-found" class="flex flex-col items-center py-6 text-center">
        <span class="flex size-14 items-center justify-center rounded-full bg-gray-100 text-gray-500 dark:bg-slate-800 dark:text-gray-400">
          <.icon name="hero-question-mark-circle" class="size-7" />
        </span>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight text-gray-900 dark:text-white">
          {gettext("Form not found")}
        </h1>
        <p class="mt-2 text-[15px] text-gray-600 dark:text-gray-400">
          {gettext("Check the link, or ask whoever sent it for a new one.")}
        </p>
      </div>
    </.shell>
    """
  end

  def forbidden(assigns) do
    ~H"""
    <.shell>
      <div id="form-forbidden" class="flex flex-col items-center py-6 text-center">
        <h1 class="text-2xl font-semibold tracking-tight text-gray-900 dark:text-white">
          {gettext("You can't try this form")}
        </h1>
        <p class="mt-2 text-[15px] text-gray-600 dark:text-gray-400">
          {gettext("Your role in this workspace can't run flows.")}
        </p>
      </div>
    </.shell>
    """
  end

  attr :test, :any, default: nil
  slot :inner_block, required: true

  defp shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 dark:bg-slate-950">
      <div
        :if={@test}
        id="form-test-banner"
        class="border-b border-amber-200 bg-amber-50 px-4 py-2.5 text-center text-sm text-amber-900 dark:border-amber-900/40 dark:bg-amber-900/20 dark:text-amber-200"
      >
        <.icon name="hero-beaker-mini" class="mr-1 size-4 align-[-3px]" />
        {gettext("Testing the draft of %{flow}. Sending runs the draft, not what is published.",
          flow: @test.name
        )}
      </div>
      <main class="mx-auto flex min-h-[calc(100vh-3rem)] max-w-xl flex-col justify-center px-4 py-10 sm:py-16">
        <div class="h-1.5 rounded-t-2xl bg-primary" />
        <div class="rounded-b-2xl border border-t-0 border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900 sm:p-10">
          {render_slot(@inner_block)}
        </div>
        <p class="mt-6 flex items-center justify-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
          <img src={~p"/images/logo.png"} alt="" class="size-4 object-contain opacity-80" />
          {gettext("Made with Heddle")}
        </p>
      </main>
    </div>
    """
  end
end
