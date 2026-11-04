<p align="center">
  <img src="apps/heddle_ui/assets/img/logo.png" alt="Heddle" width="180" />
</p>

<h2 align="center">Heddle</h2>

<p align="center">
  <em>The logic behind your business.</em>
</p>

<p align="center">
  <a href="https://hex.pm/packages/fusion_flow"><img src="https://img.shields.io/hexpm/v/fusion_flow?style=flat-square&color=6e4a7e&label=hex.pm" alt="Hex.pm" /></a>&nbsp;
  <a href="https://hexdocs.pm/fusion_flow"><img src="https://img.shields.io/badge/docs-hexdocs-8b5cf6?style=flat-square&logo=elixir&logoColor=white" alt="Docs" /></a>&nbsp;
  <a href="https://github.com/heddlehq/heddle/blob/main/LICENSE"><img src="https://img.shields.io/github/license/heddlehq/heddle?style=flat-square&color=blue" alt="License" /></a>&nbsp;
  <a href="https://github.com/heddlehq/heddle/stargazers"><img src="https://img.shields.io/github/stars/heddlehq/heddle?style=flat-square&color=f5a623&logo=github&cacheSeconds=86400" alt="GitHub Stars" /></a>&nbsp;
  <a href="https://discord.gg/7zjnpna239"><img src="https://img.shields.io/discord/1474594465225117740?style=flat-square&color=5865F2&logo=discord&logoColor=white&label=community" alt="Discord" /></a>
</p>

---

**Heddle** is a powerful, low-code workflow automation platform equipped with advanced no-code capabilities. Designed for reliability and scalability, it enables users to visually design, manage, and execute complex business logic and data processing flows in real-time.

Whether you are automating simple tasks or orchestrating complex microservices, Heddle provides the visual tools to build without boundaries.

## 🚀 Getting Started

To get **Heddle** up and running, please refer to our full **[Installation Guide](https://hexdocs.pm/fusion_flow/installation.html)**.

For deployment topology and worker scaling, see [guides/scaling.md](guides/scaling.md).

Quick local start with Docker Compose:

```bash
docker compose up -d --build db ui worker
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

## 🤝 Community & Contributing

We believe in building in public. Join our community to discuss ideas, track our vision, or help us build:

- **Contributing**: Check our [Contributing Guide](CONTRIBUTING.md) to get started.
- **Public Roadmap**: Long-term vision and goals on our [Roadmap Repository](https://github.com/heddlehq/roadmap).
- **Project Board**: Live active tasks on our [GitHub Project Board](https://github.com/orgs/heddlehq/projects/2).
- **Discord Server**: Real-time chat and support in our [Discord Server](https://discord.gg/7zjnpna239).

## License

Heddle is open-source software licensed under the [MIT license](LICENSE).
