defmodule EmployinWeb.RegistrationLive do
  @moduledoc """
  Profile setup for first-time users.

  It is reached with a `:registration` token that proves the email was verified.
  After the user is created, the form is submitted to
  `SessionController.login/2` with a short-lived `:session` token.
  """
  use EmployinWeb, :live_view

  import EmployinWeb.AuthComponents

  alias Employin.LoginToken
  alias Employin.Users
  alias Employin.Users.User

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case LoginToken.verify(:registration, token) do
      {:ok, email} ->
        {:ok,
         socket
         |> assign(:page_title, "Registration")
         |> assign(:email, email)
         |> assign(:token, "")
         |> assign(:trigger_submit, false)
         |> assign(:form, %User{} |> Ecto.Changeset.change() |> to_form())}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid or expired registration link. Please try again.")
         |> redirect(to: ~p"/login")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:error, "You don't have access to that page! Please login.")
     |> redirect(to: ~p"/login")}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      %User{}
      |> User.change_display_name(Map.take(params, ["display_name"]))
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    attrs = %{"email" => socket.assigns.email, "display_name" => params["display_name"]}

    case Users.create_user(attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:token, LoginToken.sign(:session, user.id))
         |> assign(:trigger_submit, true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          if Keyword.has_key?(changeset.errors, :email) do
            put_flash(socket, :error, "An account with this email already exists. Please log in.")
          else
            socket
          end

        {:noreply, assign(socket, form: to_form(changeset, action: :insert))}
    end
  end
end
