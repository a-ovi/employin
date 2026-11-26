defmodule EmployinWeb.LoginLive do
  @moduledoc """
  Two-step passwordless login.

    1. The user enters an email. We email them a one-time password and a magic link.
    2. The user enters the OTP. Once it is verified, the form is submitted to
       `SessionController.otp_check/2` (`phx-trigger-action`) to set the session cookie.

  Resending is throttled server-side by `@resend_cooldown` seconds.
  """
  use EmployinWeb, :live_view

  import EmployinWeb.AuthComponents

  alias Employin.LoginToken
  alias Employin.MailNotifier
  alias Employin.Users.User

  @resend_cooldown 120

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Log In")
      |> assign(:resend_cooldown, @resend_cooldown)
      |> reset_to_email_step()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      %User{}
      |> User.change_email(params)
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("send-otp", %{"user" => params}, socket) do
    changeset = User.change_email(%User{}, params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{email: email}} ->
        socket =
          socket
          |> assign(:step, :enter_otp)
          |> assign(:email, email)
          |> assign(:otp_form, to_form(%{"otp" => ""}))
          |> deliver_otp("OTP sent", "Can't send OTP. Please try again.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("resend-otp", _params, socket) do
    if System.monotonic_time(:second) >= socket.assigns.resend_available_at do
      {:noreply, deliver_otp(socket, "OTP sent again", "Can't resend OTP. Please try again.")}
    else
      {:noreply, put_flash(socket, :error, "Please wait before requesting a new code.")}
    end
  end

  def handle_event("countdown-finished", _params, socket) do
    {:noreply, assign(socket, :show_countdown, false)}
  end

  def handle_event("submit-otp", %{"otp" => otp}, socket) do
    case LoginToken.verify_otp(socket.assigns.token, otp) do
      {:ok, _email} ->
        {:noreply, assign(socket, trigger_submit: true)}

      {:error, _} ->
        form = to_form(%{"otp" => ""}, errors: [otp: {"invalid or expired code", []}])
        {:noreply, assign(socket, otp_form: form)}
    end
  end

  def handle_event("back-to-email", _params, socket) do
    {:noreply, reset_to_email_step(socket)}
  end

  defp reset_to_email_step(socket) do
    socket
    |> assign(:step, :enter_email)
    |> assign(:email, "")
    |> assign(:token, "")
    |> assign(:trigger_submit, false)
    |> assign(:show_countdown, false)
    |> assign(:resend_available_at, 0)
    |> assign(:form, %User{} |> Ecto.Changeset.change() |> to_form())
    |> assign(:otp_form, to_form(%{"otp" => ""}))
  end

  defp deliver_otp(socket, success_msg, error_msg) do
    email = socket.assigns.email
    %{token: token, otp: otp} = LoginToken.create_otp_and_token(email)
    url = url(~p"/login/verify?token=#{token}&otp=#{otp}")

    socket =
      case MailNotifier.login_instructions(email, url, otp) do
        {:ok, _meta} -> put_flash(socket, :info, success_msg)
        {:error, _reason} -> put_flash(socket, :error, error_msg)
      end

    socket
    |> assign(:token, token)
    |> assign(:show_countdown, true)
    |> assign(:resend_available_at, System.monotonic_time(:second) + @resend_cooldown)
  end
end
