defmodule EmployinWeb.HomeLive do
  use EmployinWeb, :live_view

  alias Employin.Events
  alias Employin.Events.Event

  @impl true
  def mount(_params, session, socket) do
    tz_offset = get_tz_offset(socket)
    user_id = session["user_id"]
    current_status = Events.current_status(user_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Employin.PubSub, "events")
    end

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:user_id, user_id)
      |> assign(:tz_offset, tz_offset)
      |> assign(:current_status, current_status)
      |> assign(:show_event_modal, false)
      |> assign_async(:events, fn -> {:ok, %{events: Events.get_events()}} end)

    {:ok, socket}
  end

  @impl true
  def handle_event("join", params, socket) do
    user_id = socket.assigns.user_id

    with {:ok, event} <- Events.create_event(user_id, params) do
      Phoenix.PubSub.broadcast(Employin.PubSub, "events", {:new_event, event})
    end

    socket =
      socket
      |> assign(:current_status, Event.joined())

    {:noreply, socket}
  end

  @impl true
  def handle_event("leave", params, socket) do
    user_id = socket.assigns.user_id

    with {:ok, event} <- Events.create_event(user_id, params) do
      Phoenix.PubSub.broadcast(Employin.PubSub, "events", {:new_event, event})
    end

    socket =
      socket
      |> assign(:current_status, Event.left())

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
  def handle_event("validate-form", %{"date_form" => form_fields} = params, socket) do
    IO.inspect(params)

    form =
      form_fields
      |> Event.form_changeset()
      |> to_form(action: :validate, as: :date_form)

    socket =
      socket
      |> assign(form: form)

    IO.inspect(form, label: "validate------------------------> ")

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
            join_attrs = %{type: Event.joined(), time: starting_dt}
            leave_attrs = %{type: Event.left(), time: ending_dt}

            for attrs <- [join_attrs, leave_attrs] do
              with {:ok, event} <- Events.create_event(user_id, attrs) do
                Phoenix.PubSub.broadcast(Employin.PubSub, "events", {:new_event, event})
              end
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
            IO.inspect(form, label: "form->>>>>>>>>>>>>>>> ")
            socket = assign(socket, form: form)
            {:noreply, socket}
          end
        end
    end
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
    socket = assign_async(socket, :events, fn -> {:ok, %{events: Events.get_events()}} end)
    {:noreply, socket}
  end

  def create_utc_date_time_from_form_fields(params, tz_offset) do
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

    if Mix.env() == :dev, do: IO.inspect(result, label: "#{prefix} date ->>>>>>")

    result
  end

  defp format_time(date_time, tz_offset) do
    date_time
    |> DateTime.shift(minute: tz_offset)
    |> Calendar.strftime("%d %b %I:%M %p")
  end

  defp get_tz_offset(socket) do
    get_connect_params(socket)["tz_offset"] || 0
  end
end
