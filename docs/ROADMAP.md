# Roadmap

Ideas for taking Employin further, roughly ordered by value.

## Done

These items from earlier versions of this roadmap are implemented:

- **Security:** rate-limited login codes (per address and per token), and
  single-use login links.
- **Dependencies:** all locked packages free of known advisories. Upgraded to
  Phoenix 1.8 and LiveView 1.2.
- **CI:** Credo (strict) and Dialyzer in CI.
- **Sessions:** editing and deleting your own work sessions.
- **Reports:** hours per person per day (week/month) with CSV export.
- **Time zones:** IANA time zones with DST-aware conversions.
- **Performance:** a LiveView stream for the activity log.

## Security & operations

- **Distributed rate limiting:** the Hammer ETS backend is per node. When
  running a cluster, switch to a shared backend (e.g. Redis) or Hammer's
  distributed backend.
- **Dependabot** for Mix and GitHub Actions.
- **Health check endpoint** for container orchestration.
- **Tailwind 4** and Phoenix 1.8's newer layout convention (a `<Layouts.app>` function component instead of the app layout template).

## Product

- **Audit trail:** record who changed or deleted a session, and when.
- **Roles:** an admin role to manage users, edit anyone's sessions, and put
  LiveDashboard behind authentication in production.
- **Filters** in the activity log (by user, location, date).
- **Configurable locations** instead of the hard-coded Remote / On-site list.
- **Reports:** per-location breakdown, overtime highlighting, custom date ranges.

## UX

- **i18n:** route UI strings through Gettext, with locale-aware date/time formatting.
- **Dark mode** and an accessibility pass (focus states, screen reader labels for status dots).
- **PWA:** the web manifest exists, and a service worker would make the app installable.
