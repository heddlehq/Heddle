defmodule HeddleUI.Components.ResultFile do
  @moduledoc """
  Shows the file a run produced, like an image from `AI: Generate Image`.

  Files travel through a run as base64, which is no use to read on a screen.
  """

  use Phoenix.Component
  use Gettext, backend: HeddleUI.Gettext

  @image_types ~w(image/png image/jpeg image/webp image/gif)

  attr :value, :any, required: true
  attr :id, :string, required: true

  def result_file(assigns) do
    assigns = assign(assigns, :file, file(assigns.value))

    ~H"""
    <div :if={@file} id={@id} class="mb-3">
      <img
        :if={@file.kind == :image}
        src={@file.src}
        alt={gettext("Image from this run")}
        class="max-h-96 rounded-lg border border-gray-200 dark:border-slate-800"
      />
      <audio :if={@file.kind == :audio} src={@file.src} controls class="w-full"></audio>
    </div>
    """
  end

  @doc """
  Replaces the base64 of the files in `value` with their size.
  """
  def shorten(%{"encoding" => "base64", "content" => content} = file) when is_binary(content) do
    Map.put(file, "content", gettext("(%{size} KB)", size: div(byte_size(content) * 3, 4096)))
  end

  def shorten(%{} = map), do: Map.new(map, fn {key, value} -> {key, shorten(value)} end)
  def shorten(list) when is_list(list), do: Enum.map(list, &shorten/1)
  def shorten(value), do: value

  defp file(%{"encoding" => "base64", "content" => content, "type" => type})
       when is_binary(content) and is_binary(type) do
    cond do
      type in @image_types -> %{kind: :image, src: source(type, content)}
      String.starts_with?(type, "audio/") -> %{kind: :audio, src: source(type, content)}
      true -> nil
    end
  end

  defp file(%{"result" => result}), do: file(result)
  defp file(_value), do: nil

  defp source(type, content), do: "data:#{type};base64,#{content}"
end
