defmodule HeddleNodes.Nodes.Redis.RunCommand do
  use Bobbin.Node

  alias HeddleNodes.Integration
  alias HeddleNodes.Services.Redis

  definition do
    Redis.definition(
      "Run Command",
      ~s(Runs any command, as a JSON list like ["SADD", "tags", "{{tag}}"].),
      [%{type: :textarea, name: :command, label: "Command", default: ""}]
    )
  end

  @impl true
  def handler(context, _input) do
    Redis.run(context, fn conn ->
      with {:ok, command} <- command(context),
           {:ok, reply} <- Redis.command(conn, command) do
        {:ok, %{"reply" => reply}}
      end
    end)
  end

  defp command(context) do
    case Integration.json(context, "command") do
      {:ok, [_name | _args] = command} -> {:ok, Enum.map(command, &to_string/1)}
      {:ok, _other} -> {:error, ~s(Command: give a list, like ["GET", "name"].)}
      {:error, message} -> {:error, message}
    end
  end
end
