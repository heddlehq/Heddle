defmodule HeddleNodes.Services.Imap do
  @moduledoc """
  A small IMAP client, for the Email nodes that read a mailbox.

  It only speaks IMAP over TLS, so a password never travels in the clear. Emails
  are addressed by UID, which stays the same between connections.
  """

  alias HeddleNodes.Integration

  @port 993
  @timeout :timer.seconds(30)
  @summary "BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT DATE)]"

  @doc """
  Logs in, calls `fun` with the connection, and logs out.
  """
  def session(imap, fun) do
    with {:ok, socket} <- connect(imap) do
      try do
        with :ok <- login(socket, imap), do: fun.(socket)
      after
        _reply = command(socket, ["LOGOUT"])
        :ssl.close(socket)
      end
    end
  end

  def select(socket, folder), do: status(command(socket, ["SELECT ", string(folder)]))
  def examine(socket, folder), do: status(command(socket, ["EXAMINE ", string(folder)]))

  @doc """
  Returns the UIDs that match, oldest first.

  Takes `:unread`, `:from`, `:subject` and `:uid`.
  """
  def search(socket, filters) do
    criteria = criteria(filters)
    utf8? = Enum.any?(criteria, &match?({:literal, _value}, &1))
    charset = if utf8?, do: ["CHARSET UTF-8 "], else: []

    with {:ok, items} <- command(socket, ["UID SEARCH "] ++ charset ++ criteria) do
      {:ok, Enum.flat_map(items, &search_uids/1)}
    end
  end

  @doc """
  Returns the headers of these emails, newest first.
  """
  def headers(_socket, []), do: {:ok, []}

  def headers(socket, uids) do
    with {:ok, items} <- fetch(socket, Enum.join(uids, ","), @summary) do
      {:ok, Enum.sort_by(items, & &1.uid, :desc)}
    end
  end

  @doc """
  Returns a whole email, without marking it as read.
  """
  def message(socket, uid) do
    with {:ok, [email | _rest]} <- fetch(socket, to_string(uid), "BODY.PEEK[]") do
      {:ok, email}
    end
  end

  def add_flag(socket, uid, flag), do: store(socket, uid, "+FLAGS.SILENT", flag)
  def remove_flag(socket, uid, flag), do: store(socket, uid, "-FLAGS.SILENT", flag)

  def move(socket, uid, folder) do
    with {:ok, capabilities} <- capabilities(socket) do
      if "MOVE" in capabilities do
        status(command(socket, ["UID MOVE #{uid} ", string(folder)]))
      else
        with :ok <- status(command(socket, ["UID COPY #{uid} ", string(folder)])) do
          expunge(socket, uid, capabilities)
        end
      end
    end
  end

  def delete(socket, uid) do
    with {:ok, capabilities} <- capabilities(socket) do
      expunge(socket, uid, capabilities)
    end
  end

  # A plain EXPUNGE also removes what someone else flagged in this folder.
  defp expunge(socket, uid, capabilities) do
    with :ok <- add_flag(socket, uid, "\\Deleted") do
      if "UIDPLUS" in capabilities do
        status(command(socket, ["UID EXPUNGE #{uid}"]))
      else
        status(command(socket, ["EXPUNGE"]))
      end
    end
  end

  defp store(socket, uid, action, flag) do
    status(command(socket, ["UID STORE #{uid} #{action} (#{flag})"]))
  end

  defp capabilities(socket) do
    with {:ok, items} <- command(socket, ["CAPABILITY"]) do
      {:ok, items |> Enum.map_join(" ", & &1.text) |> String.upcase() |> String.split()}
    end
  end

  defp fetch(socket, uids, part) do
    with {:ok, items} <- command(socket, ["UID FETCH #{uids} (UID FLAGS #{part})"]) do
      {:ok, items |> Enum.filter(&(&1.literals != [])) |> Enum.map(&fetched/1)}
    end
  end

  defp fetched(%{text: text, literals: [raw | _rest]}) do
    [_match, uid] = Regex.run(~r/\bUID (\d+)/, text)

    flags =
      case Regex.run(~r/\bFLAGS \(([^)]*)\)/, text) do
        [_match, flags] -> String.split(flags)
        nil -> []
      end

    %{uid: String.to_integer(uid), flags: flags, raw: raw}
  end

  defp search_uids(%{text: "* SEARCH" <> uids}) do
    uids |> String.split() |> Enum.map(&String.to_integer/1)
  end

  defp search_uids(_item), do: []

  defp criteria(filters) do
    filters
    |> Enum.flat_map(fn
      {:unread, true} -> ["UNSEEN"]
      {:unread, false} -> []
      {:uid, uid} -> ["UID #{uid}"]
      {_filter, ""} -> []
      {:from, value} -> ["FROM", string(value)]
      {:subject, value} -> ["SUBJECT", string(value)]
    end)
    |> case do
      [] -> ["ALL"]
      criteria -> Enum.intersperse(criteria, " ")
    end
  end

  # Anything but plain ASCII goes as a literal, which also keeps a line break in
  # a value from starting a new command.
  defp string(value) do
    if value =~ ~r/\A[\x20-\x7e]*\z/ do
      ~s("#{String.replace(value, ~r/(["\\])/, "\\\\\\1")}")
    else
      {:literal, value}
    end
  end

  defp connect(imap) do
    host = imap["host"]
    tls = Integration.tls_options(host)
    options = [:binary, active: false, packet: :line, buffer: 65_536] ++ tls

    case :ssl.connect(String.to_charlist(host), port(imap), options, @timeout) do
      {:ok, socket} -> greeting(socket)
      {:error, reason} -> {:error, "Could not reach the email server: #{describe(reason)}"}
    end
  end

  defp describe({:tls_alert, {_alert, details}}), do: details |> to_string() |> String.trim()
  defp describe(reason) when is_atom(reason), do: to_string(:inet.format_error(reason))
  defp describe(reason), do: inspect(reason)

  defp greeting(socket) do
    case line(socket) do
      {:ok, "* OK" <> _rest} ->
        {:ok, socket}

      _other ->
        :ssl.close(socket)
        {:error, "The email server refused the connection."}
    end
  end

  defp port(imap) do
    case Integer.parse(to_string(imap["port"])) do
      {port, ""} -> port
      _other -> @port
    end
  end

  defp login(socket, imap) do
    status(command(socket, ["LOGIN ", string(imap["username"]), " ", string(imap["password"])]))
  end

  defp status({:ok, _items}), do: :ok
  defp status({:error, _message} = error), do: error

  defp command(socket, parts) do
    tag = "H#{System.unique_integer([:positive])}"

    with :ok <- write(socket, [tag, " " | parts]) do
      read(socket, tag, [])
    end
  end

  defp write(socket, parts) do
    case Enum.split_while(parts, &is_binary/1) do
      {ready, []} ->
        send_data(socket, [ready, "\r\n"])

      {ready, [{:literal, value} | rest]} ->
        with :ok <- send_data(socket, [ready, "{#{byte_size(value)}}\r\n"]),
             :ok <- continuation(socket),
             :ok <- send_data(socket, value) do
          write(socket, rest)
        end
    end
  end

  defp continuation(socket) do
    case line(socket) do
      {:ok, "+" <> _rest} -> :ok
      {:ok, reply} -> {:error, refused(reply)}
      {:error, _message} = error -> error
    end
  end

  defp send_data(socket, data) do
    case :ssl.send(socket, data) do
      :ok -> :ok
      {:error, _reason} -> {:error, "The email server closed the connection."}
    end
  end

  defp read(socket, tag, items) do
    with {:ok, line} <- line(socket) do
      if String.starts_with?(line, tag <> " ") do
        finish(String.replace_prefix(line, tag <> " ", ""), items)
      else
        with {:ok, item} <- item(socket, line, %{text: "", literals: []}) do
          read(socket, tag, [item | items])
        end
      end
    end
  end

  defp finish("OK" <> _rest, items), do: {:ok, Enum.reverse(items)}
  defp finish(reply, _items), do: {:error, refused(reply)}

  defp refused(reply), do: "The email server refused it: #{String.trim(reply)}"

  # A line ending in {size} is followed by that many bytes, and then goes on.
  defp item(socket, line, item) do
    case Regex.run(~r/\{(\d+)\}\r\n\z/, line, capture: :all_but_first) do
      [size] ->
        with {:ok, literal} <- literal(socket, String.to_integer(size)),
             {:ok, next} <- line(socket) do
          item(socket, next, %{text: item.text <> line, literals: item.literals ++ [literal]})
        end

      nil ->
        {:ok, %{item | text: String.trim_trailing(item.text <> line)}}
    end
  end

  defp literal(_socket, 0), do: {:ok, ""}

  defp literal(socket, size) do
    :ok = :ssl.setopts(socket, packet: :raw)
    result = receive_data(socket, size)
    :ok = :ssl.setopts(socket, packet: :line)
    result
  end

  # A line longer than the buffer arrives in pieces.
  defp line(socket, start \\ "") do
    with {:ok, data} <- receive_data(socket, 0) do
      if String.ends_with?(data, "\n") do
        {:ok, start <> data}
      else
        line(socket, start <> data)
      end
    end
  end

  defp receive_data(socket, size) do
    case :ssl.recv(socket, size, @timeout) do
      {:ok, data} -> {:ok, data}
      {:error, _reason} -> {:error, "The email server stopped answering."}
    end
  end
end
