<p align="center">
  <img src="apps/heddle_ui/assets/img/logo.png" alt="Heddle" width="180" />
</p>

<h2 align="center">Heddle</h2>

<p align="center">
  <em>The logic behind your business.</em>
</p>

<p align="center">
  <a href="https://hex.pm/packages/heddle"><img src="https://img.shields.io/hexpm/v/heddle?style=flat-square&color=6e4a7e&label=hex.pm" alt="Hex.pm" /></a>&nbsp;
  <a href="https://heddlehq.github.io/website/docs/"><img src="https://img.shields.io/badge/docs-heddle-a63a2b?style=flat-square" alt="Docs" /></a>&nbsp;
  <a href="https://github.com/heddlehq/heddle/blob/main/LICENSE"><img src="https://img.shields.io/github/license/heddlehq/heddle?style=flat-square&color=blue" alt="License" /></a>&nbsp;
  <a href="https://github.com/heddlehq/heddle/stargazers"><img src="https://img.shields.io/github/stars/heddlehq/heddle?style=flat-square&color=f5a623&logo=github&cacheSeconds=86400" alt="GitHub Stars" /></a>&nbsp;
  <a href="https://discord.gg/7zjnpna239"><img src="https://img.shields.io/discord/1474594465225117740?style=flat-square&color=5865F2&logo=discord&logoColor=white&label=community" alt="Discord" /></a>
</p>

---

**Heddle** is a powerful, low-code workflow automation platform equipped with advanced no-code capabilities. Designed for reliability and scalability, it enables users to visually design, manage, and execute complex business logic and data processing flows in real-time.

Whether you are automating simple tasks or orchestrating complex microservices, Heddle provides the visual tools to build without boundaries.

## 🚀 Getting Started

Install Heddle with one line. Nothing else is required: it asks what you want, including your AI provider and whether to add [Treadle](https://github.com/heddlehq/Treadle), the terminal editor.

```bash
# Linux and macOS
curl -fsSL https://heddlehq.github.io/website/install.sh | sh
```

```powershell
# Windows
irm https://heddlehq.github.io/website/install.ps1 | iex
```

Then `heddle status`, `heddle logs -f`, `heddle doctor` and `heddle update` take it from there: `heddle --help` lists everything.

For servers and other options, see the **[Installation Guide](https://heddlehq.github.io/website/docs/start/installation/)**. For deployment topology and worker scaling, see [Scaling](https://heddlehq.github.io/website/docs/self-hosting/scaling/). To bring your team in, see [Workspaces and roles](https://heddlehq.github.io/website/docs/concepts/workspaces/).

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

## ⚡ Benchmark

Same flow, same machine, default settings, against Windmill, Kestra, n8n and Activepieces.

<p align="center">
  <img src="benchmark/compare/benchmark.gif" alt="Animated charts of the benchmark. Heddle does 387 runs per second against 108 for the runner-up, 395 with a slow API, one run takes 11 ms, and it lost no calls in a crash, repeating 50. It also uses the least idle memory and disk." width="800" />
</p>

We wrote this test, and Heddle is in it, so everything is meant to be checked and rerun: see the [method and the raw data](benchmark/compare).

## 🤝 Community & Contributing

We believe in building in public. Join our community to discuss ideas, track our vision, or help us build:

- **Contributing**: Check our [Contributing Guide](CONTRIBUTING.md) to get started.
- **Public Roadmap**: Long-term vision and goals on our [Roadmap Repository](https://github.com/heddlehq/roadmap).
- **Project Board**: Live active tasks on our [GitHub Project Board](https://github.com/orgs/heddlehq/projects/2).
- **Discord Server**: Real-time chat and support in our [Discord Server](https://discord.gg/7zjnpna239).

## License

Heddle is open-source software licensed under the [MIT license](LICENSE).
