<p align="center">
  <img src="apps/heddle_ui/assets/img/logo.png" alt="Heddle" width="180" />
</p>

<h2 align="center">Heddle</h2>

<p align="center">
  <em>The logic behind your business.</em>
</p>

<p align="center">
  <a href="https://hex.pm/packages/heddle"><img src="https://img.shields.io/hexpm/v/heddle?style=flat-square&color=6e4a7e&label=hex.pm" alt="Hex.pm" /></a>&nbsp;
  <a href="https://hexdocs.pm/heddle"><img src="https://img.shields.io/badge/docs-hexdocs-8b5cf6?style=flat-square&logo=elixir&logoColor=white" alt="Docs" /></a>&nbsp;
  <a href="https://github.com/heddlehq/heddle/blob/main/LICENSE"><img src="https://img.shields.io/github/license/heddlehq/heddle?style=flat-square&color=blue" alt="License" /></a>&nbsp;
  <a href="https://github.com/heddlehq/heddle/stargazers"><img src="https://img.shields.io/github/stars/heddlehq/heddle?style=flat-square&color=f5a623&logo=github&cacheSeconds=86400" alt="GitHub Stars" /></a>&nbsp;
  <a href="https://discord.gg/7zjnpna239"><img src="https://img.shields.io/discord/1474594465225117740?style=flat-square&color=5865F2&logo=discord&logoColor=white&label=community" alt="Discord" /></a>
</p>

---

**Heddle** is a powerful, low-code workflow automation platform equipped with advanced no-code capabilities. Designed for reliability and scalability, it enables users to visually design, manage, and execute complex business logic and data processing flows in real-time.

Whether you are automating simple tasks or orchestrating complex microservices, Heddle provides the visual tools to build without boundaries.

## 🚀 Getting Started

Install and start Heddle with one line. Nothing else is required.

```bash
# Linux and macOS
curl -fsSL https://heddlehq.github.io/website/install.sh | sh
```

```powershell
# Windows
irm https://heddlehq.github.io/website/install.ps1 | iex
```

For servers and other options, see the **[Installation Guide](guides/installation.md)**. For deployment topology and worker scaling, see [guides/scaling.md](guides/scaling.md).

Quick local start with Docker Compose:

```bash
docker compose up -d --build
```

Quick local start from source requires two terminals:

```bash
cd apps/heddle_ui
mix phx.server
```

```bash
cd apps/heddle_worker
mix run --no-halt
```

## 🧩 Building your own nodes

Nodes are written in Elixir with **[Bobbin](https://github.com/heddlehq/Bobbin)**, the SDK for extending Heddle. It's on [Hex](https://hex.pm/packages/bobbin), and Heddle's own nodes are built with it:

```elixir
def deps do
  [
    {:bobbin, "~> 0.2"}
  ]
end
```

```elixir
defmodule MyNodes.Greet do
  use Bobbin.Node

  definition do
    %{
      name: "Greet",
      title: "Greet",
      category: :utility,
      inputs: [:exec],
      outputs: [:exec]
    }
  end

  @impl true
  def handler(context, _input) do
    {:ok, Map.put(context, "result", "Hello!"), :exec}
  end
end
```

The API docs are on [HexDocs](https://hexdocs.pm/bobbin). Heddle can't load outside nodes yet, so for now a new node goes in [`apps/heddle_nodes`](apps/heddle_nodes).

## 🤝 Community & Contributing

We believe in building in public. Join our community to discuss ideas, track our vision, or help us build:

- **Contributing**: Check our [Contributing Guide](CONTRIBUTING.md) to get started.
- **Public Roadmap**: Long-term vision and goals on our [Roadmap Repository](https://github.com/heddlehq/roadmap).
- **Project Board**: Live active tasks on our [GitHub Project Board](https://github.com/orgs/heddlehq/projects/2).
- **Discord Server**: Real-time chat and support in our [Discord Server](https://discord.gg/7zjnpna239).

## License

Heddle is open-source software licensed under the [MIT license](LICENSE).
