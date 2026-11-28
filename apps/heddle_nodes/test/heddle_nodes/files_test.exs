defmodule HeddleNodes.FilesTest do
  # Swaps the credential store, which is global.
  use HeddleCore.DataCase, async: false

  alias Bobbin.Integration
  alias HeddleNodes.Manifests

  @manifest """
  id: drive
  name: Drive
  version: 1.0.0
  base_url: https://api.drive.test/
  credential:
    label: Drive
    fields: [{name: token, label: Token, secret: true}]
    auth: {type: bearer, token: "{{credential.token}}"}
  actions:
    - name: Download
      fields: [{name: id, label: File ID}]
      request: {method: GET, path: "files/{{fields.id}}"}
      output:
        file: {name: "{{fields.id}}.txt"}
    - name: Upload
      fields: [{name: file, label: File, type: file}]
      request:
        method: POST
        path: upload
        body_type: binary
        body: "{{fields.file}}"
  """

  defmodule Vault do
    def fetch(_workspace_id, "drive", "drive"), do: {:ok, %{"token" => "t"}}
  end

  setup do
    previous = Application.get_env(:heddle_nodes, :credentials_client)
    Application.put_env(:heddle_nodes, :credentials_client, Vault)
    on_exit(fn -> Application.put_env(:heddle_nodes, :credentials_client, previous) end)

    {:ok, manifest} = Integration.parse(@manifest)
    %{manifest: manifest}
  end

  test "a downloaded file is kept in Heddle and passed on as a reference, which another node uploads",
       %{manifest: manifest} do
    Req.Test.stub(HeddleNodes.Nodes.HttpRequest, fn conn ->
      case conn.request_path do
        "/files/report" ->
          conn |> Plug.Conn.put_resp_content_type("text/plain") |> Plug.Conn.send_resp(200, "hi")

        "/upload" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          Req.Test.json(conn, %{"got" => body})
      end
    end)

    context = %{"credential" => "drive", "workspace_id" => 1, "id" => "report"}

    assert {:ok, %{"result" => %{"file" => ref}}, "success"} =
             Manifests.run(manifest, "Download", context)

    assert %{"name" => "report.txt", "size" => 2} = ref
    assert HeddleCore.Files.read(ref) == {:ok, "hi"}

    upload = %{"credential" => "drive", "workspace_id" => 1, "file" => %{"file" => ref}}

    assert {:ok, %{"result" => %{"got" => "hi"}}, "success"} =
             Manifests.run(manifest, "Upload", upload)
  end
end
