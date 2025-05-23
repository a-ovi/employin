defmodule EmployinWeb.HomeLive do
  alias Phoenix.LiveView.AsyncResult
  use EmployinWeb, :live_view

  alias Employin.Events
  alias Employin.Events.Event

  @per_page 30

  @impl true
  def mount(_params, session, socket) do
    tz_offset = get_tz_offset(socket)
    user_id = session["user_id"]
    event = Events.get_last_event_by_user_id(user_id)
    current_status = Events.current_status_by_event(event)
    current_location = Events.current_location_by_event(event)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Employin.PubSub, "events")
    end

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:user_id, user_id)
      |> assign(:tz_offset, tz_offset)
      |> assign(:current_status, current_status)
      |> assign(:current_location, current_location)
      |> assign(:show_event_modal, false)
      |> assign(:page, 1)
      |> assign(:more_events?, true)
      |> assign(:events, [])
      |> assign(:quick_event_form, to_form(%{"tags" => current_location}, as: :quick_event_form))
      |> assign(:events_loader, AsyncResult.loading())
      |> start_async(:task_events_loader, fn ->
        Events.get_events(page: 1, per_page: @per_page)
      end)

    {:ok, socket}
  end

  @impl true
  def handle_async(:task_events_loader, {:ok, events}, socket) do
    %{events_loader: events_loader} = socket.assigns
    events = extract_event_fields(events)

    socket =
      socket
      |> assign(:events, events)
      |> assign(:more_events?, length(events) == @per_page)
      |> assign(:events_loader, AsyncResult.ok(events_loader, "ok"))

    {:noreply, socket}
  end

  @impl true
  def handle_async(:task_events_loader, {:exit, reason}, socket) do
    %{events_loader: events_loader} = socket.assigns

    socket =
      socket
      |> assign(:events_loader, AsyncResult.failed(events_loader, {:error, reason}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("create-quick-event", params, socket) do
    attrs = Map.get(params, "quick_event_form", %{})

    type =
      if socket.assigns.current_status == Event.joined() do
        Event.left()
      else
        Event.joined()
      end

    tags = Map.get(attrs, "tags", socket.assigns.current_location)
    attrs = %{"type" => type, "tags" => tags}
    user_id = socket.assigns.user_id

    create_event_and_broadcast_slimmed_event(user_id, attrs)

    socket =
      socket
      |> assign(:current_status, type)
      |> assign(:current_location, tags)
      |> assign(:quick_event_form, to_form(%{"tags" => tags}, as: :quick_event_form))

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_event_modal", _params, socket) do
    today = Date.utc_today()

    event_form = %{
      "starting_date" => today,
      "ending_date" => today
    }

    event_form = to_form(event_form, as: "date_form")

    socket =
      socket
      |> assign(:show_event_modal, true)
      |> assign(:form, event_form)

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
  def handle_event("validate-form", %{"date_form" => form_fields} = _params, socket) do
    form =
      form_fields
      |> Event.form_changeset()
      |> to_form(action: :validate, as: :date_form)

    socket =
      socket
      |> assign(form: form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit-form", %{"date_form" => form_fields} = _params, socket) do
    form_changeset = Event.form_changeset(form_fields)

    case form_changeset.valid? do
      false ->
        form = to_form(form_changeset, action: :validate, as: :date_form)
        socket = assign(socket, form: form)
        {:noreply, socket}

      true ->
        %{starting: starting_dt, ending: ending_dt} =
          create_utc_date_time_from_form_fields(form_fields, socket.assigns.tz_offset)

        if not DateTime.after?(ending_dt, starting_dt) do
          form_changeset =
            form_changeset
            |> Ecto.Changeset.add_error(
              :ending_date_time,
              "ending date-time must be after starting date-time"
            )
            |> Map.put(:action, :validate)

          form = to_form(form_changeset, as: :date_form)
          socket = assign(socket, form: form)
          {:noreply, socket}
        else
          if Events.can_insert?(socket.assigns.user_id, starting_dt, ending_dt) do
            user_id = socket.assigns.user_id
            join_attrs = %{type: Event.joined(), time: starting_dt, tags: form_fields["tags"]}
            leave_attrs = %{type: Event.left(), time: ending_dt, tags: form_fields["tags"]}

            for attrs <- [join_attrs, leave_attrs] do
              create_event_and_broadcast_slimmed_event(user_id, attrs)
            end

            socket =
              socket
              |> assign(:show_event_modal, false)
              |> put_flash(:info, "Event Created Successfully!")

            {:noreply, socket}
          else
            form_changeset =
              form_changeset
              |> Ecto.Changeset.add_error(
                :overlap,
                "overlaps with existing events"
              )
              |> Map.put(:action, :validate)

            form = to_form(form_changeset, as: :date_form)
            socket = assign(socket, form: form)
            {:noreply, socket}
          end
        end
    end
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    events = Events.get_events(page: page, per_page: @per_page)
    more_events? = length(events) == @per_page

    events =
      events
      |> extract_event_fields()
      |> Kernel.++(socket.assigns.events)
      |> Enum.uniq_by(fn e -> e.id end)
      |> sort_events_by_time()

    socket =
      socket
      |> assign(:events, events)
      |> assign(:page, page)
      |> assign(:more_events?, more_events?)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_event, event}, socket) do
    socket =
      if event.user_id == socket.assigns.user_id do
        socket
        |> assign(:current_status, Events.current_status_by_event(event))
        |> assign(:current_location, Events.current_location_by_event(event))
      else
        socket
      end

    {:noreply, maybe_add_event_to_socket(socket, event)}
  end

  defp create_utc_date_time_from_form_fields(params, tz_offset) do
    starting = process_datetime(params, "starting", tz_offset)
    ending = process_datetime(params, "ending", tz_offset)

    %{starting: starting, ending: ending}
  end

  defp process_datetime(params, prefix, tz_offset) do
    date = params["#{prefix}_date"]
    hour = String.to_integer(params["#{prefix}_hour"] || "0")
    minute = String.to_integer(params["#{prefix}_minute"] || "0")
    period = params["#{prefix}_period"]

    hour =
      case {hour, period} do
        {12, "am"} -> 0
        {12, "pm"} -> 12
        {h, "pm"} -> h + 12
        {h, _} -> h
      end

    {:ok, date} = Date.from_iso8601(date)
    {:ok, time} = Time.new(hour, minute, 0)
    {:ok, dt} = DateTime.new(date, time)

    result = DateTime.shift(dt, minute: -tz_offset)

    result
  end

  defp format_time(date_time, tz_offset) do
    date_time
    |> DateTime.shift(minute: tz_offset)
    |> Calendar.strftime("%I:%M %p")
  end

  defp get_tz_offset(socket) do
    get_connect_params(socket)["tz_offset"] || 0
  end

  defp sort_events_by_time(events) do
    Enum.sort_by(
      events,
      fn event ->
        event.time || event.inserted_at
      end,
      DateTime
    )
  end

  defp extract_event_fields(events) when is_list(events) do
    Enum.map(events, &extract_event_fields(&1))
  end

  defp extract_event_fields(event) when is_map(event) do
    %{
      id: event.id,
      user_id: event.user_id,
      time: event.time,
      type: event.type,
      tags: event.tags,
      inserted_at: event.inserted_at,
      user: %{
        display_name: event.user && event.user.display_name,
        email: event.user && event.user.email
      }
    }
  end

  defp event_between_current_events?(event, events) do
    event_time = event.time || event.inserted_at
    [first_event | _] = events
    first_event_time = first_event.time || first_event.inserted_at

    DateTime.compare(event_time, first_event_time) in [:gt, :eq]
  end

  defp maybe_add_event_to_socket(socket, event) do
    events = socket.assigns.events

    if events == [] or event_between_current_events?(event, events) do
      events =
        event
        |> List.wrap()
        |> Kernel.++(events)
        |> sort_events_by_time()

      assign(socket, :events, events)
    else
      socket
    end
  end

  defp group_events_by_date(events, tz_offset) do
    events
    |> Enum.group_by(&tz_shifted_iso_date(&1.time || &1.inserted_at, tz_offset))
    |> Map.to_list()
    |> Enum.sort()
  end

  defp tz_shifted_iso_date(dt, tz_offset) do
    dt
    |> DateTime.shift(minute: tz_offset)
    |> Date.to_iso8601()
  end

  defp create_event_and_broadcast_slimmed_event(user_id, attrs) do
    with {:ok, event} <- Events.create_event(user_id, attrs) do
      event =
        event
        |> Events.preload_user()
        |> extract_event_fields()

      Phoenix.PubSub.broadcast(Employin.PubSub, "events", {:new_event, event})
    end
  end
end
