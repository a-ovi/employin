defmodule EmployinWeb.HomeLive do
  use EmployinWeb, :live_view

  alias Employin.Events
  alias Employin.Events.Event

  @impl true
  def mount(_params, session, socket) do
    tz_offset = get_tz_offset(socket)
    user_id = session["user_id"]
    current_status = Events.current_status(user_id)
    events = Events.get_events()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Employin.PubSub, "events")
    end

    # event_form =
    #   %{"start_date" => Date.utc_today(), "end_date" => Date.utc_today()}
    #   |> to_form()

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:user_id, user_id)
      |> assign(:tz_offset, tz_offset)
      |> assign(:events, events)
      |> assign(:current_status, current_status)
      |> assign(:show_event_modal, false)
      # |> assign(:event_form, %{})

    {:ok, socket}
  end

  @impl true
  def handle_event("join", params, socket) do
    user_id = socket.assigns.user_id

    with {:ok, event} <- Events.create_event(user_id, params) do
      Phoenix.PubSub.broadcast(Employin.PubSub, "events", {:new_event, event})
    end

    events = Events.get_events()
    socket =
      socket
      |> assign(:current_status, Event.joined())
      |> assign(:events, events)

    {:noreply, socket}
  end

  @impl true
  def handle_event("leave", params, socket) do
    user_id = socket.assigns.user_id

    with {:ok, event} <- Events.create_event(user_id, params) do
      Phoenix.PubSub.broadcast(Employin.PubSub, "events", {:new_event, event})
    end

    events = Events.get_events()
    socket =
      socket
      |> assign(:current_status, Event.left())
      |> assign(:events, events)

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_event_modal", _params, socket) do
    event_form =
      %{"start_date" => Date.utc_today(), "end_date" => Date.utc_today()}
      |> to_form()

    socket =
      socket
      |> assign(:show_event_modal, true)
      |> assign(:event_form, event_form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_event", params, socket) do
    IO.inspect(params, label: "--------->")

    socket =
      socket
      |> assign(:show_event_modal, false)


    {:noreply, socket}
  end

  @impl true
  def handle_event("close_modal", _unsigned_params, socket) do
    socket =
      socket
      |> assign(:show_event_modal, false)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_event, _event}, socket) do
    events = Events.get_events()
    {:noreply, assign(socket, :events, events)}
  end

  def format_time(date_time, tz_offset \\ 0) do
    date_time
    |> DateTime.shift(minute: tz_offset)
    |> Calendar.strftime("%d %b %I:%M %p")
  end

  defp get_tz_offset(socket) do
    get_connect_params(socket)["tz_offset"] || 0
  end

end
