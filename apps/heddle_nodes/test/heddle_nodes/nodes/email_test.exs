defmodule HeddleNodes.Nodes.EmailTest do
  use ExUnit.Case, async: false

  alias HeddleNodes.Nodes.Email

  defmodule Vault do
    # A run asks within its workspace, which these tests leave out.
    def fetch(_workspace_id, name, kind), do: fetch(name, kind)

    def fetch("bad-address", "smtp"),
      do: {:ok, %{"host" => "127.0.0.1", "port" => "1", "from" => "a@b.co"}}

    def fetch("smtp", "smtp") do
      port = :persistent_term.get({__MODULE__, :smtp})
      {:ok, %{"host" => "127.0.0.1", "port" => to_string(port), "from" => "a@b.co"}}
    end

    def fetch("imap", "imap") do
      port = :persistent_term.get({__MODULE__, :imap})

      {:ok,
       %{
         "host" => "localhost",
         "port" => to_string(port),
         "username" => "ana",
         "password" => "s\"3\\cret"
       }}
    end

    def fetch(name, _kind), do: {:error, "no #{inspect(name)}"}
  end

  setup_all do
    key = {:namedCurve, :secp256r1}
    root = :public_key.pkix_test_root_cert(~c"Test root", digest: :sha256, key: key)
    san = {:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}

    %{server_config: server, client_config: client} =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: root,
          intermediates: [],
          peer: [digest: :sha256, key: key, extensions: [san]]
        },
        client_chain: %{root: root, intermediates: [], peer: [digest: :sha256, key: key]}
      })

    %{tls: server, cacerts: client[:cacerts]}
  end

  setup %{cacerts: cacerts} do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    Application.put_env(:heddle_nodes, :cacerts, cacerts)

    on_exit(fn ->
      Application.put_env(:heddle_nodes, :credentials_client, previous)
      Application.delete_env(:heddle_nodes, :cacerts)
    end)
  end

  # A mailbox that answers `reply` and tells the test what it was asked.
  defp start_imap(%{tls: tls}, reply) do
    test = self()

    {:ok, listener} =
      :ssl.listen(0, [:binary, active: false, packet: :line, reuseaddr: true] ++ tls)

    {:ok, {_address, port}} = :ssl.sockname(listener)
    :persistent_term.put({Vault, :imap}, port)

    start_supervised!({Task, fn -> accept_imap(listener, reply, test) end})
  end

  defp accept_imap(listener, reply, test) do
    {:ok, socket} = :ssl.transport_accept(listener)
    {:ok, socket} = :ssl.handshake(socket)
    :ok = :ssl.send(socket, "* OK ready\r\n")
    serve_imap(socket, reply, test)
    accept_imap(listener, reply, test)
  end

  defp serve_imap(socket, reply, test) do
    case read_command(socket, "") do
      {:ok, line} ->
        [tag, command] = String.split(String.trim(line), " ", parts: 2)
        send(test, {:imap, command})
        {lines, status} = answer(command, reply)
        :ok = :ssl.send(socket, [lines, tag, " ", status, "\r\n"])
        serve_imap(socket, reply, test)

      :closed ->
        :ok
    end
  end

  defp read_command(socket, start) do
    case :ssl.recv(socket, 0, 5000) do
      {:ok, data} ->
        line = start <> data

        case Regex.run(~r/\{(\d+)\}\r\n\z/, line, capture: :all_but_first) do
          [size] -> read_command(socket, line <> read_literal(socket, String.to_integer(size)))
          nil -> {:ok, line}
        end

      {:error, _reason} ->
        :closed
    end
  end

  defp read_literal(socket, size) do
    :ok = :ssl.send(socket, "+ go\r\n")
    :ok = :ssl.setopts(socket, packet: :raw)
    {:ok, literal} = :ssl.recv(socket, size, 5000)
    :ok = :ssl.setopts(socket, packet: :line)
    literal
  end

  defp answer(command, reply) do
    case reply.(command) do
      nil -> default_answer(command)
      {lines, status} -> {lines, status}
      lines -> {lines, "OK done"}
    end
  end

  defp default_answer("LOGOUT"), do: {"* BYE\r\n", "OK bye"}
  defp default_answer("CAPABILITY"), do: {"* CAPABILITY IMAP4rev1 MOVE UIDPLUS\r\n", "OK done"}
  defp default_answer("UID SEARCH UID " <> id), do: {"* SEARCH #{id}\r\n", "OK done"}
  defp default_answer(_command), do: {"", "OK done"}

  defp search_command do
    receive do
      {:imap, "UID SEARCH" <> _rest = command} -> command
      {:imap, _other} -> search_command()
    after
      0 -> flunk("The server wasn't asked to search.")
    end
  end

  defp fetch_line(sequence, uid, flags, raw) do
    "* #{sequence} FETCH (UID #{uid} FLAGS (#{flags}) BODY[] {#{byte_size(raw)}}\r\n#{raw})\r\n"
  end

  describe "List Emails" do
    @headers "From: =?ISO-8859-1?Q?Jos=E9?= <j@x.co>\r\nTo: a@b.co\r\n" <>
               "Subject: =?UTF-8?B?UmVsYXTDs3Jpbw==?=\r\nDate: Fri, 6 Nov 2026 10:00:00 -0300\r\n\r\n"

    test "returns the latest ones first, with readable headers", context do
      start_imap(context, fn
        "UID SEARCH ALL" ->
          "* SEARCH 1 2 3\r\n"

        "UID FETCH 2,3 " <> _rest ->
          [fetch_line(1, 2, "\\Seen", @headers), fetch_line(2, 3, "", @headers)]

        _other ->
          nil
      end)

      node = %{"credential" => "imap", "folder" => "INBOX", "limit" => "2"}

      assert {:ok, %{"result" => [newest, oldest]}, "success"} = Email.List.handler(node, nil)

      assert %{
               "id" => 3,
               "unread" => true,
               "from" => "José <j@x.co>",
               "subject" => "Relatório"
             } = newest

      assert %{"id" => 2, "unread" => false} = oldest

      assert_received {:imap, ~S(LOGIN "ana" "s\"3\\cret")}
      assert_received {:imap, ~S(EXAMINE "INBOX")}
    end

    test "filters on the server, sending accents as a literal", context do
      start_imap(context, fn _command -> nil end)

      node = %{
        "credential" => "imap",
        "only_unread" => "yes",
        "from" => "ana@x.co",
        "subject" => "Relatório"
      }

      assert {:ok, %{"result" => []}, "success"} = Email.List.handler(node, nil)

      command = search_command()

      assert command =~ ~S(UID SEARCH CHARSET UTF-8 UNSEEN FROM "ana@x.co" SUBJECT {10})
      assert command =~ "Relatório"
    end

    test "a value can't start a new command", context do
      start_imap(context, fn _command -> nil end)

      node = %{"credential" => "imap", "subject" => "x\r\nA1 DELETE INBOX"}

      assert {:ok, _context, "success"} = Email.List.handler(node, nil)

      assert String.starts_with?(search_command(), "UID SEARCH CHARSET UTF-8 SUBJECT {")
      refute_received {:imap, "DELETE" <> _rest}
    end

    test "takes the error output when the login fails", context do
      start_imap(context, fn
        "LOGIN " <> _rest -> {"", "NO wrong password"}
        _other -> nil
      end)

      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               Email.List.handler(%{"credential" => "imap"}, nil)

      assert message =~ "wrong password"
      refute message =~ "cret"
    end

    test "takes the error output when the certificate can't be trusted", context do
      start_imap(context, fn _command -> nil end)
      Application.put_env(:heddle_nodes, :cacerts, :public_key.cacerts_get())

      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               Email.List.handler(%{"credential" => "imap"}, nil)

      assert message =~ "Could not reach"
    end
  end

  describe "Get Email" do
    @multipart Enum.join(
                 [
                   "From: j@x.co",
                   "Subject: Oi",
                   "MIME-Version: 1.0",
                   ~s(Content-Type: multipart/mixed; boundary="b1"),
                   "",
                   "--b1",
                   "Content-Type: text/plain; charset=ISO-8859-1",
                   "Content-Transfer-Encoding: quoted-printable",
                   "",
                   "Ol=E1",
                   "--b1",
                   "Content-Type: text/html; charset=UTF-8",
                   "",
                   "<b>Olá</b>",
                   "--b1",
                   ~s(Content-Type: application/pdf; name="a.pdf"),
                   ~s(Content-Disposition: attachment; filename="a.pdf"),
                   "Content-Transfer-Encoding: base64",
                   "",
                   "aGVsbG8=",
                   "--b1--",
                   ""
                 ],
                 "\r\n"
               )

    test "returns the content without marking it as read", context do
      start_imap(context, fn
        "UID FETCH 7 " <> _rest -> fetch_line(1, 7, "", @multipart)
        _other -> nil
      end)

      node = %{"credential" => "imap", "id" => "{{result.id}}", "result" => %{"id" => 7}}

      assert {:ok, %{"result" => email}, "success"} = Email.Get.handler(node, nil)

      assert %{"id" => 7, "subject" => "Oi", "unread" => true} = email
      assert String.trim(email["text"]) == "Olá"
      assert String.trim(email["html"]) == "<b>Olá</b>"

      assert email["attachments"] == [
               %{"name" => "a.pdf", "type" => "application/pdf", "size" => 5}
             ]

      assert_received {:imap, ~S(EXAMINE "INBOX")}
      assert_received {:imap, "UID SEARCH UID 7"}
      assert_received {:imap, "UID FETCH 7 (UID FLAGS BODY.PEEK[])"}
    end

    test "takes the error output when the email isn't there", context do
      start_imap(context, fn
        "UID SEARCH UID 7" -> "* SEARCH\r\n"
        _other -> nil
      end)

      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               Email.Get.handler(%{"credential" => "imap", "id" => "7"}, nil)

      assert message =~ "no email 7"
    end

    test "refuses an ID that isn't a number before connecting" do
      :persistent_term.put({Vault, :imap}, 1)

      for id <- ["", "abc", "1 DELETE", "-1"] do
        assert {:ok, %{"result" => %{"error" => _message}}, "error"} =
                 Email.Get.handler(%{"credential" => "imap", "id" => id}, nil)
      end
    end
  end

  describe "changing an email" do
    @node %{"credential" => "imap", "id" => "7", "folder" => "Clientes"}

    test "marks it as read and unread", context do
      start_imap(context, fn _command -> nil end)

      assert {:ok, %{"result" => %{"id" => 7}}, "success"} = Email.MarkRead.handler(@node, nil)
      assert_received {:imap, ~S(SELECT "Clientes")}
      assert_received {:imap, ~S|UID STORE 7 +FLAGS.SILENT (\Seen)|}

      assert {:ok, _context, "success"} = Email.MarkUnread.handler(@node, nil)
      assert_received {:imap, ~S|UID STORE 7 -FLAGS.SILENT (\Seen)|}
    end

    test "doesn't touch an email that isn't there", context do
      start_imap(context, fn
        "UID SEARCH UID 7" -> "* SEARCH\r\n"
        _other -> nil
      end)

      assert {:ok, _context, "error"} = Email.MarkRead.handler(@node, nil)
      refute_received {:imap, "UID STORE" <> _rest}
    end

    test "moves it", context do
      start_imap(context, fn _command -> nil end)

      node = Map.put(@node, "target_folder", "Arquivo")

      assert {:ok, %{"result" => %{"folder" => "Arquivo"}}, "success"} =
               Email.Move.handler(node, nil)

      assert_received {:imap, ~S|UID MOVE 7 "Arquivo"|}
    end

    test "moves it on a server without MOVE, removing only this email", context do
      start_imap(context, fn
        "CAPABILITY" -> "* CAPABILITY IMAP4rev1 UIDPLUS\r\n"
        _other -> nil
      end)

      node = Map.put(@node, "target_folder", "Arquivo")

      assert {:ok, _context, "success"} = Email.Move.handler(node, nil)
      assert_received {:imap, ~S|UID COPY 7 "Arquivo"|}
      assert_received {:imap, ~S|UID STORE 7 +FLAGS.SILENT (\Deleted)|}
      assert_received {:imap, "UID EXPUNGE 7"}
    end

    test "deletes it", context do
      start_imap(context, fn _command -> nil end)

      assert {:ok, _context, "success"} = Email.Delete.handler(@node, nil)
      assert_received {:imap, ~S|UID STORE 7 +FLAGS.SILENT (\Deleted)|}
      assert_received {:imap, "UID EXPUNGE 7"}
    end

    test "takes the error output when the server refuses it", context do
      start_imap(context, fn
        "UID EXPUNGE 7" -> {"", "NO read only"}
        _other -> nil
      end)

      assert {:ok, %{"result" => %{"error" => message}}, "error"} =
               Email.Delete.handler(@node, nil)

      assert message =~ "read only"
    end
  end

  describe "Send Email" do
    # Just enough of a mail server to keep what it's given.
    defp start_smtp do
      test = self()
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: :line])
      {:ok, port} = :inet.port(listener)
      :persistent_term.put({Vault, :smtp}, port)

      start_supervised!(
        {Task,
         fn ->
           {:ok, socket} = :gen_tcp.accept(listener)
           :ok = :gen_tcp.send(socket, "220 ready\r\n")
           serve_smtp(socket, test, [])
         end}
      )
    end

    defp serve_smtp(socket, test, recipients) do
      case :gen_tcp.recv(socket, 0, 5000) do
        {:ok, "RCPT TO:" <> rest} ->
          :ok = :gen_tcp.send(socket, "250 ok\r\n")
          serve_smtp(socket, test, [String.trim(rest) | recipients])

        {:ok, "DATA" <> _rest} ->
          :ok = :gen_tcp.send(socket, "354 go\r\n")
          send(test, {:smtp, Enum.reverse(recipients), read_data(socket, "")})
          :ok = :gen_tcp.send(socket, "250 ok\r\n")
          serve_smtp(socket, test, recipients)

        {:ok, "QUIT" <> _rest} ->
          :gen_tcp.send(socket, "221 bye\r\n")

        {:ok, _other} ->
          :ok = :gen_tcp.send(socket, "250 ok\r\n")
          serve_smtp(socket, test, recipients)

        {:error, _reason} ->
          :ok
      end
    end

    defp read_data(socket, data) do
      case :gen_tcp.recv(socket, 0, 5000) do
        {:ok, ".\r\n"} -> data
        {:ok, line} -> read_data(socket, data <> line)
      end
    end

    @email %{
      "credential" => "smtp",
      "to" => "x@y.co",
      "cc" => "c@y.co",
      "bcc" => "secret@y.co",
      "subject" => "Oi\r\nBcc: evil@y.co",
      "message" => "<b>Hi</b>",
      "format" => "html"
    }

    test "reaches everyone, and keeps the Bcc out of the message" do
      start_smtp()

      assert {:ok, %{"result" => %{"sent_to" => sent_to}}, "success"} =
               Email.Send.handler(@email, nil)

      assert sent_to == ["x@y.co", "c@y.co", "secret@y.co"]

      assert_receive {:smtp, recipients, data}, 5000
      assert recipients == ["<x@y.co>", "<c@y.co>", "<secret@y.co>"]

      {_type, _subtype, headers, _params, _body} = :mimemail.decode(data, encoding: :none)
      names = Enum.map(headers, fn {name, _value} -> String.downcase(name) end)

      assert "cc" in names
      refute "bcc" in names
      refute data =~ "secret@y.co"
      assert data =~ "text/html"
    end

    test "attaches a file a Download node returned" do
      start_smtp()

      email =
        Map.merge(@email, %{
          "attachment_name" => "a.bin",
          "attachment" => "{{result}}",
          "result" => %{"content" => "//4=", "encoding" => "base64"}
        })

      assert {:ok, _context, "success"} = Email.Send.handler(email, nil)

      assert_receive {:smtp, _recipients, data}, 5000

      assert {"multipart", "mixed", _headers, _params, [_text, attachment]} =
               :mimemail.decode(data, encoding: :none)

      assert {"application", "octet-stream", _attachment_headers, params, <<255, 254>>} =
               attachment

      assert {"filename", "a.bin"} in params.disposition_params
    end

    test "refuses bad addresses before connecting" do
      for {field, value} <- [{"to", ""}, {"to", "nobody"}, {"cc", "nope"}, {"bcc", "a@b.co, x"}] do
        node = Map.put(%{"credential" => "bad-address", "to" => "a@b.co"}, field, value)

        assert {:ok, %{"result" => %{"error" => message}}, "error"} =
                 Email.Send.handler(node, nil)

        refute message =~ "email failed"
      end
    end

    test "takes the error output when the server can't be reached" do
      node = %{
        "credential" => "bad-address",
        "to" => "x@y.co",
        "subject" => "s",
        "message" => "m"
      }

      assert {:ok, %{"result" => %{"error" => message}}, "error"} = Email.Send.handler(node, nil)
      assert message =~ "email failed"
    end
  end
end
