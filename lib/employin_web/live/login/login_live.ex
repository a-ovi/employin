defmodule EmployinWeb.LoginLive do
  @moduledoc """
  Two-step passwordless login.

    1. The user enters an email. We email them a one-time password and a magic link.
    2. The user enters the OTP. Once it is verified, the form is submitted to
       `SessionController.otp_check/2` (`phx-trigger-action`) to set the session cookie.

  The OTP step lives in the URL (`/login?s=...`) as an encrypted, short-lived
  `:pending` token (email, OTP token, time sent). Refreshing the page keeps the
  user on the OTP step, and `handle_params/3` is the only place that decides
  which step is shown.

  Resending is throttled server-side by `@resend_cooldown` seconds, measured
  from the time stored in the pending token, so a refresh doesn't reset it.
  """
  use EmployinWeb, :live_view

  import EmployinWeb.AuthComponents

  alias Employin.Auth
  alias Employin.LoginToken
  alias Employin.MailNotifier
  alias Employin.Users.User

  @resend_cooldown 120

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Log In")
     |> assign(:trigger_submit, false)
     |> assign(:form, empty_email_form())
     |> assign(:otp_form, to_form(%{"otp" => ""}))}
  end

  @impl true
  def handle_params(%{"s" => state}, _uri, socket) do
    case LoginToken.decrypt(:pending, state) do
      {:ok, %{email: email, token: token, sent_at: sent_at}} ->
        {:noreply, assign_otp_step(socket, email, token, sent_at)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your verification code has expired. Please request a new one.")
         |> assign_email_step()}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign_email_step(socket)}
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
        {:noreply, deliver_otp(socket, email, "OTP sent", "Can't send OTP. Please try again.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("resend-otp", _params, socket) do
    %{email: email, resend_available_at: available_at} = socket.assigns

    if now() >= available_at do
      {:noreply,
       deliver_otp(socket, email, "OTP sent again", "Can't resend OTP. Please try again.")}
    else
      {:noreply, put_flash(socket, :error, "Please wait before requesting a new code.")}
    end
  end

  def handle_event("countdown-finished", _params, socket) do
    {:noreply, assign(socket, :show_countdown, false)}
  end

  def handle_event("submit-otp", %{"otp" => otp}, socket) do
    case Auth.verify_code(socket.assigns.token, otp) do
      {:ok, _email} ->
        {:noreply, assign(socket, trigger_submit: true)}

      {:error, {:rate_limited, _}} ->
        {:noreply, assign_otp_error(socket, "too many attempts, please request a new code")}

      {:error, _} ->
        {:noreply, assign_otp_error(socket, "invalid or expired code")}
    end
  end

  def handle_event("back-to-email", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/login")}
  end

  defp assign_email_step(socket) do
    socket
    |> assign(:step, :enter_email)
    |> assign(:email, "")
    |> assign(:token, "")
    |> assign(:show_countdown, false)
    |> assign(:countdown_seconds, 0)
    |> assign(:resend_available_at, 0)
    |> assign(:form, empty_email_form())
    |> assign(:otp_form, to_form(%{"otp" => ""}))
  end

  defp assign_otp_step(socket, email, token, sent_at) do
    available_at = sent_at + @resend_cooldown
    remaining = max(available_at - now(), 0)

    socket
    |> assign(:step, :enter_otp)
    |> assign(:email, email)
    |> assign(:token, token)
    |> assign(:resend_available_at, available_at)
    |> assign(:countdown_seconds, remaining)
    |> assign(:show_countdown, remaining > 0)
    |> assign(:otp_form, to_form(%{"otp" => ""}))
  end

  defp assign_otp_error(socket, message) do
    assign(socket, otp_form: to_form(%{"otp" => ""}, errors: [otp: {message, []}]))
  end

  defp deliver_otp(socket, email, success_msg, error_msg) do
    case Auth.request_code(email) do
      {:ok, code} ->
        send_code(socket, email, code, success_msg, error_msg)

      {:error, {:rate_limited, retry_after_ms}} ->
        minutes = max(div(retry_after_ms, 60_000), 1)

        put_flash(
          socket,
          :error,
          "Too many codes requested for this address. Try again in #{minutes} min."
        )
    end
  end

  defp send_code(socket, email, %{token: token, otp: otp}, success_msg, error_msg) do
    url = url(~p"/login/verify?token=#{token}&otp=#{otp}")

    socket =
      case MailNotifier.login_instructions(email, url, otp) do
        {:ok, _meta} -> put_flash(socket, :info, success_msg)
        {:error, _reason} -> put_flash(socket, :error, error_msg)
      end

    state = LoginToken.encrypt(:pending, %{email: email, token: token, sent_at: now()})
    push_patch(socket, to: ~p"/login?#{[s: state]}")
  end

  defp empty_email_form, do: %User{} |> Ecto.Changeset.change() |> to_form()

  defp now, do: System.system_time(:second)
end
