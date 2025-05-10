# Employin

Employin is a simple web application for companies to track when users enter or leave their workplace. Users can easily record their arrival and departure with a single click, and can also add past time points. All activity is displayed on the home page for easy review.

## Demo

<div align="center">
  <img src="docs/images/home.png" width="32%" alt="Home Page" />
  <img src="docs/images/modal.png" width="32%" alt="Time Entry Form" /> 
  <img src="docs/images/login.png" width="32%" alt="otp submit page" />
</div>

## Features

- One-click "Join" (arrival) and "Leave" (departure) tracking
- Add past time points
- Activity log displayed on the home page
- Magic Link login and registration
- Restrict registration to specific email domains (optional)

## Tech Stack

- **Backend:** Elixir, Phoenix Framework, LiveView
- **Frontend:** Tailwind CSS
- **Database:** PostgreSQL

## Getting Started

### Prerequisites

- Elixir & Erlang installed
- PostgreSQL installed and running
- Node.js (for asset compilation)
- [direnv](https://direnv.net/) (optional, for loading environment variables)

### Installation

1. **Clone the repository:**
   ```sh
   git clone <your-repo-url>
   cd employin
   ```

2. **Set up environment variables:**
   - Copy `.envrc` to your project root (or use your own method to set environment variables).
   - Edit the values as needed.

3. **Install dependencies:**
   ```sh
   mix deps.get
   cd assets && npm install && cd ..
   ```

4. **Set up the database:**
   ```sh
   mix ecto.setup
   ```

5. **Run the server:**
   ```sh
   mix phx.server
   ```
   Visit [http://localhost:4000](http://localhost:4000) in your browser.

## Environment Variables

All variables below are **required** unless otherwise noted.

| Variable         | Description                                                        |
|------------------|--------------------------------------------------------------------|
| SECRET_KEY_BASE  | Phoenix secret key (generate with `mix phx.gen.secret`)            |
| DATABASE_URL     | PostgreSQL connection string (e.g., `ecto://USER:PASS@HOST/DB`)    |
| PHX_HOST         | Hostname for the app (e.g., `localhost`, `example.com`)                           |
| ORIGINS          | Allowed CORS origins (comma-separated)                             |
| PORT             | Port to run the server on (e.g., `4000`)                           |
| TOKEN_SECRET     | Secret for token generation                                        |
| TOKEN_SALT       | Salt for token generation                                          |
| EMAIL_NAME       | Display name for outgoing emails                                   |
| EMAIL_FROM       | Email address for outgoing emails                                  |
| SMTP_USERNAME    | AWS SES SMTP username                                              |
| SMTP_PASSWORD    | AWS SES SMTP password                                              |
| SMTP_ENDPOINT    | AWS SES SMTP endpoint (e.g., `email-smtp.us-west-2.amazonaws.com`) |
| SMTP_PORT        | AWS SES SMTP port (e.g., `587`)                                    |
| EMAIL_DOMAIN     | (Optional) Restrict registration to this email domain              |

## Testing

There are currently no automated tests.

## Deployment

A Dockerfile will be added soon. For now, deploy as a standard Phoenix application.

## License

MIT
