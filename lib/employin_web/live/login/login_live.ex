defmodule EmployinWeb.LoginLive do
  use EmployinWeb, :live_view
  alias Employin.Users.User
  alias Employin.LoginToken
  alias Employin.MailNotifier

  # @impl true
  # def mount(%{"token" => token}, _session , socket) do
  #   error = [otp: {"invalid or expired otp", []}]
  #   fields = %{"otp" => ""}

  #   socket =
  #     socket
  #     |> assign(:step, :enter_otp)
  #     |> assign(:token, token)
  #     |> assign(:otp, "")
  #     |> assign(:trigger_submit, false)
  #     |> assign(:form, to_form(fields, errors: error, action: :validate))

  #   {:ok, socket}
  # end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Log In")
      |> assign(:step, :enter_email)
      |> assign(:token, "")
      |> assign(:otp, "")
      |> assign(:trigger_submit, false)
      |> assign(:form, %User{} |> Ecto.Changeset.change() |> to_form())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate",  %{"user" => user_email}, socket) do
    form =
      %User{}
      |> User.change_email(user_email)
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("send-email", %{"user" => user_email}, socket) do
    email_changeset =
      User.change_email(%User{}, user_email)

    if email_changeset.valid? do
      # create otp and token
      %{email: email} = email_changeset.changes
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(email)
      # send token via mailer
      url = get_url(token, otp)
      socket =
        case MailNotifier.login_instructions(email, url, otp) do
          {:ok, _meta} ->
            put_flash(socket, :info, "OTP Sent")
          {:error, _error} ->
            put_flash(socket, :error, "Can't send otp")
        end
      IO.inspect(otp, label: "----------> OTP")
      IO.inspect(token, label: "----------> TOKEN")
      {
        :noreply,
        socket
        |> assign(:step, :enter_otp)
        |> assign(:token, token)
        |> assign(:form, to_form(%{"otp" => ""}))
      }
    else
      {:noreply, assign(socket, form: to_form(email_changeset, action: :save))}
    end
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

  # @impl true
  # def handle_event("submit-otp", %{"otp" => otp}, socket) do
  #   {
  #     :noreply,
  #     socket
  #     |> assign(:trigger_submit, true)
  #     |> assign(:otp, otp)
  #   }
  # end

  def get_url(token, otp) do
    url(~p"/login/verify?token=#{token}&otp=#{otp}")
  end

end
