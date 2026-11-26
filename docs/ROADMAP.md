# Roadmap

Ideas for taking Employin further, roughly ordered by value.

## Security & operations

- **Rate limiting:** throttle OTP verification and login emails per email/IP
  (e.g. with [Hammer](https://hex.pm/packages/hammer)). Today the resend
  cooldown is enforced per LiveView, and `/login/verify` relies on the 5-minute
  token lifetime alone.
- **Single-use login links:** keep a short-lived record of consumed OTP tokens
  so a link can't be reused within its lifetime.
- **Dependency updates:** refresh `mix.lock` within the current version
  constraints (`mix hex.audit` and `mix deps.get` report advisories for several
  locked packages), then upgrade to Phoenix 1.8 / LiveView 1.1+ and Tailwind 4.
- **Static analysis:** add Credo and Dialyzer to CI, and enable Dependabot for Mix
  and GitHub Actions.
- **Health check endpoint** for container orchestration.

## Product

- **Edit and delete events** (with the same overlap rules), plus an audit trail.
- **Reports:** hours per user per day/week/month, CSV export.
- **Roles:** an admin role to manage users and see reports, and to put
  LiveDashboard behind authentication in production.
- **Filters** in the activity log (by user, location, date).
- **Configurable locations** instead of the hard-coded Remote / On-site list.

## Correctness & UX

- **IANA timezones:** send `Intl.DateTimeFormat().resolvedOptions().timeZone`
  instead of a fixed UTC offset, and convert with a time zone database (`tz` /
  `tzdata`). This makes past sessions across a DST change correct.
- **LiveView streams** for the activity log, so the server doesn't keep the
  loaded window in memory per connection.
- **i18n:** route UI strings through Gettext, with locale-aware date/time formatting.
- **Dark mode** and an accessibility pass (focus states, screen reader labels for status dots).
- **PWA:** the web manifest exists, and a service worker would make the app installable.
