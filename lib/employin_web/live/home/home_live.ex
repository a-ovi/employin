defmodule EmployinWeb.HomeLive do
  use EmployinWeb, :live_view

  alias Employin.Events
  alias Employin.Events.Event

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]
    current_status = Events.current_status(user_id)
    events = Events.get_events()
    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:user_id, user_id)
      |> assign(:events, events)
      |> assign(:current_status, current_status)

    {:ok, socket}
  end

  @impl true
  def handle_event("join", params, socket) do
    user_id = socket.assigns.user_id
    Events.create_event(user_id, params)
    events = Events.get_events()
    socket =
      socket
      |> assign(:current_status, Event.joined())
      |> assign(:events, events)

    {:noreply, socket}
  end

  def handle_event("leave", params, socket) do
    user_id = socket.assigns.user_id
    Events.create_event(user_id, params)
    events = Events.get_events()
    socket =
      socket
      |> assign(:current_status, Event.left())
      |> assign(:events, events)

    {:noreply, socket}
  end

  defp format_time(date_time) do
    Calendar.strftime(date_time, "%H:%M")
  end
end
