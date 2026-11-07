defmodule HeddleUI.TerminalChannel do
  @moduledoc """
  Carries the keys and the screen of one terminal, which lives as long as this does.
  """

  use Phoenix.Channel

  alias HeddleCore.Flows
  alias HeddleUI.Terminal

  @impl true
  def join("terminal:" <> flow_id, %{"cols" => cols, "rows" => rows}, socket) do
    with %{} = flow <- Flows.get_flow(socket.assigns.current_scope, flow_id),
         {:ok, terminal} <- Terminal.open(socket.assigns.current_scope, flow, {cols, rows}) do
      {:ok, assign(socket, :terminal, terminal)}
    else
      _failed -> {:error, %{reason: "unavailable"}}
    end
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) do
    Terminal.input(socket.assigns.terminal, data)
    {:noreply, socket}
  end

  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket) do
    Terminal.resize(socket.assigns.terminal, cols, rows)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:terminal_output, data}, socket) do
    push(socket, "output", {:binary, data})
    {:noreply, socket}
  end

  def handle_info(:terminal_exited, socket) do
    push(socket, "exited", %{})
    {:stop, :normal, socket}
  end
end
