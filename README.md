# Employin

[![CI](https://github.com/a-ovi/employin/actions/workflows/ci.yml/badge.svg)](https://github.com/a-ovi/employin/actions/workflows/ci.yml)

Employin is a small real-time attendance tracker built with Elixir, Phoenix and LiveView.
Team members record when they start and end work with a single click, fix or add sessions
they forgot to log, see everyone's activity update live, and export hours worked.

## Demo

<div align="center">
  <img src="docs/images/home.png" width="32%" alt="Home page with the live activity log and status card" />
  <img src="docs/images/modal.png" width="32%" alt="Form for adding a past work session" />
  <img src="docs/images/login.png" width="32%" alt="One-time password login step" />
</div>
<div align="center">
  <img src="docs/images/reports.png" width="97%" alt="Weekly report of hours per person per day" />
</div>

## Features

- **One-click start/end of work**, tagged with a location (Remote / On-site, defaulting
  to the last one used).
- **Real-time activity log** of all users, updated live over Phoenix PubSub and rendered
  with LiveView streams. Times show in each viewer's own IANA timezone (DST-aware), and
  older entries load as you scroll up.
- **Manage your sessions:** add a session you forgot to log, or edit or delete your own.
  Overlapping or impossible ranges are rejected, and writes are serialized per user.
- **Reports:** hours per person per day for any week or month, split at local midnight,
  with CSV export.
- **Passwordless login:** a one-time password and a magic link are emailed to the user.
  Links are single-use, and both sending codes and guessing them are rate-limited.
  New users pick a display name on their first login.
- **Optional domain restriction:** only allow sign-ups from your company's email domain.

## Tech stack

| Layer    | Technology |
|----------|------------|
| Backend  | Elixir 1.18, Phoenix 1.8, Phoenix LiveView 1.2, Ecto, Hammer, tz |
| Frontend | LiveView function components, Tailwind CSS, Heroicons, a few small JS hooks |
| Database | PostgreSQL (`citext`, UUIDv7 primary keys) |
| Email    | Swoosh (local mailbox in dev, SMTP / AWS SES in production) |
| Tooling  | ExUnit + LiveViewTest, Credo, Dialyzer, GitHub Actions CI, multi-stage Docker release |

The design is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and
planned improvements are in [docs/ROADMAP.md](docs/ROADMAP.md).

## Getting started

### Prerequisites

- Elixir 1.18 / Erlang OTP 27 (other versions ≥ Elixir 1.14 likely work)
- PostgreSQL 14+ running on `localhost` with user `postgres` / password `postgres`
  (see `config/dev.exs`)

Node.js is **not** required: esbuild and Tailwind are downloaded as standalone
binaries by Mix.

### Run it locally

```sh
git clone https://github.com/a-ovi/employin.git
cd employin
mix setup          # deps, database, migrations, asset tooling
mix phx.server     # or: iex -S mix phx.server
```

Open <http://localhost:4000> and log in with any email address.
In development, emails are not sent. Read the one-time password (or click the
magic link) in the local mailbox at <http://localhost:4000/dev/mailbox>.

No environment variables are needed in development. To try production-like settings,
copy [`.envrc.example`](.envrc.example) to `.envrc` (it is git-ignored) and load it with
[direnv](https://direnv.net/) or `source .envrc`.

## Testing

```sh
mix test                          # unit, controller and LiveView tests
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer                      # first run builds the PLT into priv/plts (slow)
```

The same checks run on every push and pull request in GitHub Actions.

## Deployment

The repository has a multi-stage `Dockerfile` that builds a Mix release:

```sh
docker build -t employin .

# run database migrations
docker run --rm --env-file .env employin /app/bin/migrate

# start the server
docker run -p 4000:4000 --env-file .env employin
```

Put the app behind a TLS-terminating proxy. The generated URLs use
`https://PHX_HOST`.

## Environment variables (production)

Configuration is read at boot in `config/runtime.exs`.

### Required

| Variable          | Description |
|-------------------|-------------|
| `SECRET_KEY_BASE` | Phoenix secret for cookies/sessions (`mix phx.gen.secret`) |
| `DATABASE_URL`    | PostgreSQL URL, e.g. `ecto://USER:PASS@HOST/DATABASE` |
| `TOKEN_SECRET`    | Secret for signing login/OTP tokens (`mix phx.gen.secret`) |
| `EMAIL_FROM`      | Sender address for login emails |
| `SMTP_ENDPOINT`   | SMTP relay, e.g. `email-smtp.us-west-2.amazonaws.com` |
| `SMTP_USERNAME`   | SMTP username |
| `SMTP_PASSWORD`   | SMTP password |

### Optional

| Variable            | Default       | Description |
|---------------------|---------------|-------------|
| `PHX_HOST`          | `localhost`   | Public hostname used to build URLs |
| `PORT`              | `4000`        | HTTP port |
| `ORIGINS`           | `PHX_HOST`    | Allowed WebSocket origins, comma-separated (`false` disables the check) |
| `EMAIL_NAME`        | `Employin`    | Sender display name |
| `EMAIL_DOMAIN`      | _(none)_      | Restrict sign-ups to this domain and its subdomains |
| `SMTP_PORT`         | `587`         | SMTP port (STARTTLS) |
| `TOKEN_SALT`        | `employin`    | Prefix for token salts. Changing it invalidates outstanding tokens |
| `POOL_SIZE`         | `10`          | Database connection pool size |
| `ECTO_IPV6`         | `false`       | Set to `true` to connect to the database over IPv6 |
| `PHX_SERVER`        | set by `bin/server` | Starts the HTTP server in a release |
| `DNS_CLUSTER_QUERY` | _(none)_      | DNS name used to discover other nodes for clustering |

## License

[MIT](LICENSE)
