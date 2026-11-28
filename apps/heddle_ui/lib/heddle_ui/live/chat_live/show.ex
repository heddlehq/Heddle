defmodule HeddleUI.ChatLive.Show do
  @moduledoc """
  The chat page of a trigger people talk to, like an Agent: public at `/c/:token`
  (see `HeddleCore.Chats`), and at `/flows/:id/chat/:node_id` for someone who can run
  the flow, to try it from the editor.

  The node's package does the talking (`c:Bobbin.Node.chat_message/4`) and keeps the
  conversation (`c:Bobbin.Node.chat_history/3`), which this page reads again every
  moment. Each browser is a conversation of its own, kept in its session; a test is
  one per person. Each address can send only so many messages a minute.
  """

  use HeddleUI, :live_view

  alias HeddleCore.Chats

  @refresh 1_500
  @max_length 4_000

  @impl true
  def mount(%{"token" => token}, session, socket) do
    put_locale(session)

    case Chats.published(token) do
      {:ok, chat} ->
        conversation = "chat:" <> (session["chat_visitor"] || random_id())
        open(socket, chat, conversation, test: false, key: token)

      {:error, :not_found} ->
        {:ok, missing(socket), layout: false}
    end
  end

  def mount(%{"id" => flow_id, "node_id" => node_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Chats.for_test(scope, flow_id, node_id) do
      {:ok, chat} ->
        open(socket, chat, "test:#{scope.user.id}", test: true, key: "#{flow_id}/#{node_id}")

      {:error, :not_published} ->
        {:ok, socket |> missing() |> assign(:reason, :not_published), layout: false}

      _other ->
        {:ok, missing(socket), layout: false}
    end
  end

  defp open(socket, chat, conversation, opts) do
    case chat_module(chat.node.type) do
      nil ->
        {:ok, missing(socket), layout: false}

      module ->
        if connected?(socket), do: Process.send_after(self(), :refresh, @refresh)

        socket =
          socket
          |> assign(
            chat: chat,
            module: module,
            conversation: conversation,
            test: opts[:test],
            key: opts[:key],
            title: title(chat.node),
            alert: nil,
            missing: false,
            reason: nil
          )
          |> load()

        {:ok, socket, layout: false}
    end
  end

  defp missing(socket),
    do: assign(socket, missing: true, reason: :not_found, title: gettext("Chat"), messages: [])

  @doc "The module of a node type that takes chat messages, or nil."
  def chat_module(type) do
    module = HeddleNodes.Packages.get_node_module(type)

    if module && Code.ensure_loaded?(module) && function_exported?(module, :chat_message, 4) &&
         function_exported?(module, :chat_history, 3),
       do: module
  end

  defp title(node) do
    case String.trim(to_string(node.controls["name"] || "")) do
      "" -> node.label || gettext("Chat")
      name -> name
    end
  end

  @impl true
  def handle_event("send", %{"message" => text}, socket) do
    text = text |> to_string() |> String.trim() |> String.slice(0, @max_length)

    cond do
      text == "" ->
        {:noreply, socket}

      not HeddleUI.FormRateLimit.allow?({:chat, peer(socket), socket.assigns.key}) ->
        {:noreply,
         assign(
           socket,
           :alert,
           gettext("You sent many messages in a row. Wait a minute and try again.")
         )}

      true ->
        %{chat: chat, module: module, conversation: conversation} = socket.assigns

        case module.chat_message(chat.workspace_id, chat.node.controls, conversation, text) do
          {:ok, _sent} ->
            {:noreply, socket |> assign(alert: nil) |> push_event("chat:sent", %{}) |> load()}

          {:error, message} ->
            {:noreply, assign(socket, alert: message)}
        end
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh)
    {:noreply, load(socket)}
  end

  defp load(%{assigns: %{missing: true}} = socket), do: socket

  defp load(socket) do
    %{chat: chat, module: module, conversation: conversation} = socket.assigns

    messages =
      try do
        module.chat_history(chat.workspace_id, chat.node.controls, conversation)
      rescue
        _error -> socket.assigns[:messages] || []
      end

    assign(socket, :messages, messages)
  end

  defp waiting?(messages), do: match?(%{role: :visitor}, List.last(messages))

  defp peer(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} -> :inet.ntoa(address) |> to_string()
      _none -> "unknown"
    end
  rescue
    _error -> "unknown"
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

  defp put_locale(%{"locale" => locale}) when is_binary(locale) do
    if locale in Gettext.known_locales(HeddleUI.Gettext),
      do: Gettext.put_locale(HeddleUI.Gettext, locale)
  end

  defp put_locale(_session), do: :ok

  @impl true
  def render(%{missing: true} = assigns) do
    ~H"""
    <main class="flex min-h-screen items-center justify-center bg-gray-50 px-4 dark:bg-slate-950">
      <div id="chat-missing" class="max-w-md text-center">
        <.icon name="hero-chat-bubble-left-right" class="mx-auto size-10 text-gray-400" />
        <h1 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {if @reason == :not_published,
            do: gettext("Publish the flow to talk to it"),
            else: gettext("This chat isn't here")}
        </h1>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {if @reason == :not_published,
            do: gettext("The chat talks to what is published. Publish the flow, then try again."),
            else: gettext("The link may have changed, or the flow is no longer published.")}
        </p>
      </div>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="flex h-screen flex-col bg-gray-50 dark:bg-slate-950">
      <div
        :if={@test}
        id="chat-test-banner"
        class="border-b border-amber-200 bg-amber-50 px-4 py-2 text-center text-sm text-amber-900 dark:border-amber-900/40 dark:bg-amber-900/20 dark:text-amber-200"
      >
        <.icon name="hero-beaker-mini" class="mr-1 size-4 align-[-3px]" />
        {gettext("Trying %{name}. This conversation is yours alone, and runs what is published.",
          name: @title
        )}
      </div>
      <header class="border-b border-gray-200 bg-white px-4 py-3 dark:border-slate-800 dark:bg-slate-900">
        <div class="mx-auto flex max-w-2xl items-center gap-3">
          <span class="flex size-9 items-center justify-center rounded-full bg-sky-500/15 text-sky-700 dark:text-sky-300">
            <.icon name="hero-user-circle-solid" class="size-6" />
          </span>
          <h1 id="chat-title" class="text-base font-semibold text-gray-900 dark:text-white">
            {@title}
          </h1>
        </div>
      </header>

      <main id="chat-messages" class="flex-1 overflow-y-auto px-4 py-6" phx-hook="ScrollToBottom">
        <div class="mx-auto flex max-w-2xl flex-col gap-3">
          <p
            :if={@messages == []}
            id="chat-empty"
            class="py-10 text-center text-sm text-gray-500 dark:text-gray-400"
          >
            {gettext("Send a message to start.")}
          </p>
          <div
            :for={{message, index} <- Enum.with_index(@messages)}
            id={"chat-message-#{index}"}
            class={[
              "max-w-[85%] whitespace-pre-line rounded-2xl px-4 py-2.5 text-[15px] leading-relaxed",
              if(message.role == :visitor,
                do: "self-end bg-primary text-primary-content",
                else:
                  "self-start border border-gray-200 bg-white text-gray-900 dark:border-slate-800 dark:bg-slate-900 dark:text-gray-100"
              )
            ]}
          >
            {message.text}
          </div>
          <div
            :if={waiting?(@messages)}
            id="chat-typing"
            class="self-start rounded-2xl border border-gray-200 bg-white px-4 py-2.5 text-sm text-gray-500 dark:border-slate-800 dark:bg-slate-900 dark:text-gray-400"
          >
            <span class="inline-flex gap-1">
              <span class="size-1.5 animate-bounce rounded-full bg-current" />
              <span class="size-1.5 animate-bounce rounded-full bg-current [animation-delay:150ms]" />
              <span class="size-1.5 animate-bounce rounded-full bg-current [animation-delay:300ms]" />
            </span>
          </div>
        </div>
      </main>

      <footer class="border-t border-gray-200 bg-white px-4 py-3 dark:border-slate-800 dark:bg-slate-900">
        <div
          :if={@alert}
          id="chat-alert"
          role="alert"
          class="mx-auto mb-2 max-w-2xl rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700 dark:bg-rose-900/20 dark:text-rose-300"
        >
          {@alert}
        </div>
        <form
          id="chat-form"
          phx-submit="send"
          class="mx-auto flex max-w-2xl items-end gap-2"
        >
          <textarea
            id="chat-input"
            name="message"
            rows="1"
            maxlength="4000"
            placeholder={gettext("Write a message")}
            phx-hook="SubmitOnEnter"
            class="min-h-[44px] flex-1 resize-none rounded-xl border border-gray-200 bg-white px-4 py-2.5 text-[15px] text-gray-900 placeholder-gray-400 focus:border-primary focus:outline-none focus:ring-4 focus:ring-primary/15 dark:border-slate-700 dark:bg-slate-950 dark:text-gray-100"
          ></textarea>
          <button
            id="chat-send"
            type="submit"
            class="inline-flex h-[44px] items-center gap-1 rounded-xl bg-primary px-4 text-sm font-semibold text-primary-content hover:bg-primary/90"
          >
            {gettext("Send")} <.icon name="hero-paper-airplane-mini" class="size-4" />
          </button>
        </form>
        <p class="mx-auto mt-2 flex max-w-2xl items-center justify-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
          <img src={~p"/images/logo.png"} alt="" class="size-4 object-contain opacity-80" />
          {gettext("Made with Heddle")}
        </p>
      </footer>
    </div>
    """
  end
end
