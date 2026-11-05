defmodule HeddleAI.ClaudeAgent.RunTest do
  use ExUnit.Case, async: true

  alias HeddleAI.ClaudeAgent.Run

  @moduletag :tmp_dir

  defp script(dir, body) do
    path = Path.join(dir, "fake_claude")
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp start(binary, dir, opts \\ []) do
    test = self()

    start_supervised!(
      {Run,
       [
         owner: Keyword.get(opts, :owner, self()),
         binary: binary,
         args: Keyword.get(opts, :args, []),
         env: Keyword.get(opts, :env, []),
         cwd: dir,
         on_finish: fn -> send(test, :finished) end
       ]}
    )
  end

  defp delta(text) do
    Jason.encode!(%{
      type: "stream_event",
      event: %{type: "content_block_delta", delta: %{type: "text_delta", text: text}}
    })
  end

  test "streams what the program prints", %{tmp_dir: dir} do
    binary = script(dir, "echo '#{delta("Hel")}'\necho 'noise'\necho '#{delta("lo")}'\n")

    pid = start(binary, dir)

    assert Enum.to_list(Run.stream(pid)) == [{:text_delta, "Hel"}, {:text_delta, "lo"}]
    assert_receive :finished
  end

  test "reports a failing program", %{tmp_dir: dir} do
    pid = start(script(dir, "exit 3\n"), dir)

    assert [{:error, message}] = Enum.to_list(Run.stream(pid))
    assert message =~ "status 3"
  end

  test "stops at the first error instead of hanging", %{tmp_dir: dir} do
    result = ~s({"type":"result","subtype":"x","is_error":true})
    pid = start(script(dir, "echo '#{result}'\nexit 1\n"), dir)

    assert [{:error, _message}] = Enum.to_list(Run.stream(pid))
  end

  test "gives the program a closed stdin, or claude would wait for it", %{tmp_dir: dir} do
    binary = script(dir, "cat\necho '#{delta("done")}'\n")

    assert [{:text_delta, "done"}] = binary |> start(dir) |> Run.stream() |> Enum.to_list()
  end

  test "passes arguments without a shell reading them", %{tmp_dir: dir} do
    binary = script(dir, ~s(printf '%s\\n' "$1" > "#{dir}/arg"\n))
    prompt = "$(touch #{dir}/pwned); `id`"

    binary |> start(dir, args: [prompt]) |> Run.stream() |> Enum.to_list()

    assert File.read!(Path.join(dir, "arg")) == prompt <> "\n"
    refute File.exists?(Path.join(dir, "pwned"))
  end

  test "removes variables from the program's environment", %{tmp_dir: dir} do
    System.put_env("HEDDLE_RUN_TEST_SECRET", "leak")
    on_exit(fn -> System.delete_env("HEDDLE_RUN_TEST_SECRET") end)

    binary = script(dir, ~s(printf '%s' "${HEDDLE_RUN_TEST_SECRET:-clean}" > "#{dir}/env"\n))

    binary
    |> start(dir, env: [{"HEDDLE_RUN_TEST_SECRET", false}])
    |> Run.stream()
    |> Enum.to_list()

    assert File.read!(Path.join(dir, "env")) == "clean"
  end

  test "kills the program when the owner dies", %{tmp_dir: dir} do
    pid_file = Path.join(dir, "pid")
    binary = script(dir, ~s(echo $$ > "#{pid_file}"\nexec sleep 60\n))

    owner = spawn(fn -> Process.sleep(:infinity) end)
    run = start(binary, dir, owner: owner)
    ref = Process.monitor(run)

    os_pid = wait_for_pid(pid_file)
    assert running?(os_pid)

    Process.exit(owner, :kill)

    assert_receive {:DOWN, ^ref, :process, ^run, :normal}, 2_000
    assert_receive :finished
    assert wait_until_gone(os_pid)
  end

  defp wait_for_pid(file, attempts \\ 100) do
    case File.read(file) do
      {:ok, content} when content != "" ->
        String.trim(content)

      _other when attempts > 0 ->
        :timer.sleep(20)
        wait_for_pid(file, attempts - 1)
    end
  end

  defp running?(os_pid) do
    match?({_output, 0}, System.cmd("kill", ["-0", os_pid], stderr_to_stdout: true))
  end

  defp wait_until_gone(os_pid, attempts \\ 100) do
    cond do
      not running?(os_pid) ->
        true

      attempts == 0 ->
        false

      true ->
        :timer.sleep(20)
        wait_until_gone(os_pid, attempts - 1)
    end
  end
end
