defmodule HeddleNodes.Connections do
  @moduledoc """
  Keeps the connection to a database open while runs use it.

  A For Each that writes 1000 rows shouldn't log in 1000 times, and 1000 runs at once
  shouldn't open 1000 connections. So each credential gets one supervised process,
  which owns the driver's connection and closes it after a while without use. If the
  driver dies this process goes with it, and the next run opens a new one.

  Processes are found by a hash of the credential's values, so a changed password
  gets a new connection and no secret ends up in a process name.
  """

  use GenServer, restart: :temporary

  @idle :timer.minutes(5)
  @connect_timeout :timer.seconds(45)
  # How long the reason of a failure waits for the run that asked for the connection.
  @unclaimed :timer.seconds(5)

  @doc """
  Calls `fun` with the connection for `values`, opening it with `connect` if needed.

  `connect` returns `{:ok, pid}` or `{:ok, pid, connection}`, with `pid` linked to the
  caller, or `{:error, message}`.
  """
  def with_connection(values, connect, fun) do
    key = :crypto.hash(:sha256, :erlang.term_to_binary(values))

    with {:ok, holder, connection, ref} <- checkout(key, connect, 1) do
      try do
        fun.(connection)
      after
        GenServer.cast(holder, {:checkin, ref})
      end
    end
  end

  # A connection can close just as a run asks for it, so it's worth one more try.
  defp checkout(key, connect, retries) do
    with {:ok, holder} <- holder(key, connect),
         {:ok, connection, ref} <- GenServer.call(holder, :checkout, @connect_timeout) do
      {:ok, holder, connection, ref}
    end
  catch
    :exit, {:timeout, _call} -> {:error, "The database took too long to connect."}
    :exit, _reason when retries > 0 -> checkout(key, connect, retries - 1)
    :exit, _reason -> {:error, "The connection to the database closed."}
  end

  defp holder(key, connect) do
    case DynamicSupervisor.start_child(
           HeddleNodes.Connections.Supervisor,
           {__MODULE__, {key, connect}}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, "Could not open a connection: #{inspect(reason)}"}
    end
  end

  @doc """
  Tries `connect` in a process of its own, and returns `:ok` or `{:error, message}`.

  Drivers connect in the background and only log why they couldn't, and some kill or
  trap exits in whoever calls them. This keeps the reason for the person who has to fix
  the credential. What a driver raises can print its options, which hold the password,
  so that never goes any further.
  """
  def check(connect) do
    Task.await(Task.async(fn -> safely(connect) end), :infinity)
  end

  defp safely(connect) do
    Process.flag(:trap_exit, true)

    case connect.() do
      :ok -> :ok
      {:error, message} -> {:error, "Could not connect: #{message}"}
    end
  rescue
    error -> {:error, "Could not connect: the driver failed with #{inspect(error.__struct__)}."}
  end

  def start_link({key, connect}) do
    GenServer.start_link(__MODULE__, connect, name: {:via, Registry, {__MODULE__.Registry, key}})
  end

  # Connecting happens after init, so a slow server doesn't hold the supervisor up.
  @impl true
  def init(connect), do: {:ok, %{connection: nil, users: MapSet.new()}, {:continue, connect}}

  @impl true
  def handle_continue(connect, state) do
    case open(connect) do
      {:ok, pid} -> {:noreply, %{state | connection: {:ok, pid}}, @idle}
      {:ok, _pid, connection} -> {:noreply, %{state | connection: {:ok, connection}}, @idle}
      {:error, message} -> {:noreply, %{state | connection: {:error, message}}, @unclaimed}
    end
  end

  # A driver that raises prints its options, and those hold the password. Crashing here
  # would put them in the logs, so neither the message nor the term may go any further.
  defp open(connect) do
    connect.()
  rescue
    error -> {:error, "Could not connect: the driver failed with #{inspect(error.__struct__)}."}
  end

  @impl true
  def handle_call(:checkout, _from, %{connection: {:error, _message} = error} = state) do
    {:stop, :shutdown, error, state}
  end

  def handle_call(:checkout, {caller, _tag}, %{connection: {:ok, connection}} = state) do
    ref = Process.monitor(caller)

    {:reply, {:ok, connection, ref}, %{state | users: MapSet.put(state.users, ref)}}
  end

  @impl true
  def handle_cast({:checkin, ref}, state) do
    Process.demonitor(ref, [:flush])

    release(ref, state)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state), do: release(ref, state)

  # Nobody came for an error, so there's nothing left to do here.
  def handle_info(:timeout, %{connection: {:error, _message}} = state) do
    {:stop, :shutdown, state}
  end

  def handle_info(:timeout, %{users: users} = state) do
    if MapSet.size(users) == 0, do: {:stop, :shutdown, state}, else: {:noreply, state}
  end

  defp release(ref, state) do
    users = MapSet.delete(state.users, ref)
    state = %{state | users: users}

    if MapSet.size(users) == 0, do: {:noreply, state, @idle}, else: {:noreply, state}
  end
end
