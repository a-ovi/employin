defmodule EmployinWeb.RegistrationLive do
  use EmployinWeb, :live_view

  alias Employin.LoginToken
  alias Employin.Users
  alias Employin.Users.User

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case LoginToken.verify(token, max_age: 30) do
      {:ok, email} ->
        {
          :ok,
          socket
          |> assign(:page_title, "Registration")
          |> assign(:email, email)
          |> assign(:token, "")
          |> assign(:trigger_submit, false)
          |> assign(:form, %User{} |> Ecto.Changeset.change() |> to_form())
        }

      {:error, _} ->
        {
          :ok,
          socket
          |> put_flash(:error, "Invalid or Expired registration token. Please try again.")
          |> redirect(to: ~p"/login")
        }
    end
  end

  @impl true
  def mount(_params, _sesion, socket) do
    {
      :ok,
      socket
      |> put_flash(:error, "You don't have access to that page! Please login.")
      |> redirect(to: ~p"/login")
    }
  end

  @impl true
  def handle_event("submit", %{"user" => user} = _params, socket) do
    email = socket.assigns.email
    display_name = user["display_name"]
    attrs = %{"email" => email, "display_name" => display_name}

    case Users.create_user(attrs) do
      {:ok, user} ->
        token = LoginToken.sign(user.id)
        {
          :noreply,
          socket
          |> assign(:trigger_submit, true)
          |> assign(:token, token)
        }

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :save))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user}, socket) do
    attrs = Map.take(user, ["display_name"])
    IO.inspect(attrs, label: "->>>>>>>>>atrtrs")
    form =
      %User{}
      |> User.change_display_name(attrs)
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

end
