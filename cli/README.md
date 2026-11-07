# heddle

The `heddle` command: installs Heddle and Treadle, and then runs and maintains them.
It's what the `curl | sh` on the site hands over to.

```bash
go run ./cmd/heddle install      # the wizard
go run ./cmd/heddle --help       # every command
go test ./...
```

To try an install without touching the one on your machine, give it a home of its own:

```bash
HOME=/tmp/try go run ./cmd/heddle install
```

## How it's laid out

- `internal/install` turns a `Plan` into an install. The wizard and the flags only
  differ in how they fill the `Plan`: everything that touches the machine is here.
- `internal/wizard` asks the questions and draws the install. A question is a `screen`
  in `screens.go`.
- `internal/runtime` starts and stops Heddle, with its own Postgres or with Docker.
- `internal/commands` is the command line.

Text lives at the call site in both languages: `text.T("Stopped", "Parado")`.

The palette and logos in `internal/brand` match `internal/tui` in Treadle, and the saved
session in `internal/treadle` matches `credentials.go` there.
