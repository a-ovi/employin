defmodule EmployinWeb.LoginLive do
  use EmployinWeb, :live_view
  alias Employin.Users.User
  alias Employin.LoginToken
  alias Employin.MailNotifier

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Log In")
      |> assign(:step, :enter_email)
      |> assign(:token, "")
      |> assign(:otp, "")
      |> assign(:trigger_submit, false)
      |> assign(:email, "")
      |> assign(:show_countdown, false)
      |> assign(:form, %User{} |> Ecto.Changeset.change() |> to_form())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"user" => user_email}, socket) do
    form =
      %User{}
      |> User.change_email(user_email)
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("send-otp", %{"user" => user_email}, socket) do
    email_changeset =
      User.change_email(%User{}, user_email)

    if email_changeset.valid? do
      # create otp and token
      %{email: email} = email_changeset.changes
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(email)

      socket =
        case send_email(email, token, otp) do
          {:ok, _meta} ->
            put_flash(socket, :info, "OTP Sent")

          {:error, _error} ->
            put_flash(socket, :error, "Can't send otp")
        end

      {
        :noreply,
        socket
        |> assign(:step, :enter_otp)
        |> assign(:token, token)
        |> assign(:email, email)
        |> assign(:show_countdown, true)
        |> assign(:form, to_form(%{"otp" => ""}))
      }
    else
      {:noreply, assign(socket, form: to_form(email_changeset, action: :save))}
    end
  end

  @impl true
  def handle_event("resend-otp", _unsigned_params, socket) do
    email = socket.assigns.email

    %{otp: otp, token: token} = LoginToken.create_otp_and_token(email)

    socket =
      case send_email(email, token, otp) do
        {:ok, _meta} ->
          put_flash(socket, :info, "OTP sent again")

        {:error, _error} ->
          put_flash(socket, :error, "Can't resend otp")
      end

    socket =
      socket
      |> assign(:token, token)
      |> assign(:show_countdown, true)
      |> push_event("restart-countdown", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("countdown-finished", _params, socket) do
    socket =
      socket
      |> assign(:show_countdown, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit-otp", %{"otp" => otp}, socket) do
    token = socket.assigns.token

    case LoginToken.verify_token_with_otp(token, otp) do
      {:ok, _} ->
        {:noreply, assign(socket, trigger_submit: true)}

      {:error, _} ->
        error = [otp: {"invalid or expired otp", []}]
        fields = %{"otp" => ""}

        {
          :noreply,
          assign(
            socket,
            form: to_form(fields, errors: error, action: :validate)
          )
        }
    end
  end

  def handle_event("back-to-email", _params, socket) do
    socket =
      socket
      |> assign(:step, :enter_email)
      |> assign(:token, "")
      |> assign(:otp, "")
      |> assign(:show_countdown, false)
      |> push_event("reset-global-timer", %{})
      |> assign(:form, %User{} |> Ecto.Changeset.change() |> to_form())

    {:noreply, socket}
  end

  defp send_email(email, token, otp) do
    url = get_url(token, otp)

    if Application.get_env(:employin, :env) == :prod do
      MailNotifier.login_instructions(email, url, otp)
    else
      # In development, just log to terminal instead of sending email
      IO.puts("\n=== DEVELOPMENT MODE: Email Not Sent ===")
      IO.puts("To: #{email}")
      IO.puts("URL: #{url}")
      IO.puts("OTP: #{otp}")
      IO.puts("=======================================\n")
      {:ok, "success"}
    end
  end

  defp get_url(token, otp) do
    url(~p"/login/verify?token=#{token}&otp=#{otp}")
  end
end
