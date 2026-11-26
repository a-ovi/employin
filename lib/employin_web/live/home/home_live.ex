defmodule EmployinWeb.HomeLive do
  @moduledoc """
  The main page. It has a real-time activity log of every user's events and a
  status card to start or end work. A modal adds past work sessions, or edits
  and deletes the user's own sessions.

  Business rules live in `Employin.Events`. The log is a LiveView stream
  managed by `EmployinWeb.HomeLive.ActivityLog`, paginated with keyset
  cursors ("load more" when the user scrolls to the top).
  """
  use EmployinWeb, :live_view

  import EmployinWeb.HomeComponents

  alias Employin.Events
  alias Employin.Events.Event
  alias Employin.TimeZones
  alias EmployinWeb.HomeLive.ActivityLog
  alias EmployinWeb.Layouts
  alias Phoenix.LiveView.AsyncResult

  @per_page 30

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe()

    last_event = Events.last_event(socket.assigns.current_user.id)

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:time_zone, time_zone(socket))
      |> ActivityLog.init()
      |> assign(:more_events?, true)
      |> assign(:session_modal, nil)
      |> assign_status(last_event)
      |> assign(:events_loader, AsyncResult.loading())
      |> start_async(:load_events, fn -> Events.list_events(limit: @per_page) end)

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_events, {:ok, events}, socket) do
    socket =
      socket
      |> ActivityLog.reset(events)
      |> assign(:more_events?, length(events) == @per_page)
      |> assign(:events_loader, AsyncResult.ok(socket.assigns.events_loader, true))

    {:noreply, socket}
  end

  def handle_async(:load_events, {:exit, reason}, socket) do
    loader = AsyncResult.failed(socket.assigns.events_loader, {:exit, reason})
    {:noreply, assign(socket, :events_loader, loader)}
  end

  @impl true
  def handle_event("toggle-status", params, socket) do
    tags = params |> get_in(["quick_event", "tags"]) |> blank_to_nil()

    case Events.toggle_status(socket.assigns.current_user.id, tags) do
      {:ok, event} ->
        {:noreply, assign_status(socket, event)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update your status. Please try again.")}
    end
  end

  def handle_event("show-session-modal", _params, socket) do
    today = local_today(socket)

    params = %{
      "starting_date" => today,
      "ending_date" => today,
      "tags" => socket.assigns.last_location
    }

    {:noreply, open_session_modal(socket, %{mode: :new, running?: false}, params)}
  end

  def handle_event("edit-session", %{"id" => event_id}, socket) do
    %{current_user: user, time_zone: time_zone} = socket.assigns

    case Events.get_work_session(user.id, event_id) do
      {:ok, %{joined: joined, left: left}} ->
        modal = %{mode: :edit, event_id: joined.id, running?: is_nil(left)}
        params = Event.session_form_params(joined, left, time_zone)
        {:noreply, open_session_modal(socket, modal, params)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That session can't be edited.")}
    end
  end

  def handle_event("close-session-modal", _params, socket) do
    {:noreply, assign(socket, :session_modal, nil)}
  end

  def handle_event("validate-session", %{"session" => params}, socket) do
    form =
      params
      |> session_changeset(socket)
      |> to_form(as: :session, action: :validate)

    {:noreply, assign(socket, :session_form, form)}
  end

  def handle_event("save-session", %{"session" => params}, socket) do
    %{current_user: user, time_zone: time_zone, session_modal: modal} = socket.assigns
    opts = [running?: modal.running?]

    case Event.apply_session_form(params, time_zone, DateTime.utc_now(), opts) do
      {:ok, session} ->
        result =
          case modal.mode do
            :new ->
              Events.create_work_session(user.id, session.starting, session.ending, session.tags)

            :edit ->
              Events.update_work_session(
                user.id,
                modal.event_id,
                session.starting,
                session.ending,
                session.tags
              )
          end

        handle_session_result(result, params, socket)

      {:error, changeset} ->
        {:noreply, assign(socket, :session_form, to_form(changeset, as: :session))}
    end
  end

  def handle_event("delete-session", _params, socket) do
    %{current_user: user, session_modal: %{mode: :edit, event_id: event_id}} = socket.assigns

    case Events.delete_work_session(user.id, event_id) do
      :ok ->
        {:noreply,
         socket |> assign(:session_modal, nil) |> put_flash(:info, "Work session deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't delete the session. Please try again.")}
    end
  end

  def handle_event("load-more", _params, %{assigns: %{more_events?: false}} = socket) do
    {:reply, %{more: false}, socket}
  end

  def handle_event("load-more", _params, %{assigns: %{log_window: nil}} = socket) do
    # Nothing loaded yet (initial load still running): let the client retry later.
    {:reply, %{more: true}, socket}
  end

  def handle_event("load-more", _params, socket) do
    cursor = ActivityLog.oldest_cursor(socket.assigns)
    page = Events.list_events(limit: @per_page, before: cursor)
    more? = length(page) == @per_page

    socket =
      socket
      |> ActivityLog.prepend(page)
      |> assign(:more_events?, more?)

    {:reply, %{more: more?}, socket}
  end

  @impl true
  def handle_info({:new_events, events}, socket) do
    user_id = socket.assigns.current_user.id

    socket =
      case events |> Enum.filter(&(&1.user_id == user_id)) |> List.last() do
        nil -> socket
        latest -> assign_status(socket, Events.last_event(user_id) || latest)
      end

    {:noreply, add_events(socket, events)}
  end

  def handle_info({:events_changed, user_id}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id,
        do: assign_status(socket, Events.last_event(user_id)),
        else: socket

    {:noreply, reload_log(socket, [])}
  end

  ## Helpers

  defp open_session_modal(socket, modal, params) do
    socket = assign(socket, :session_modal, modal)
    assign(socket, :session_form, params |> session_changeset(socket) |> to_form(as: :session))
  end

  defp session_changeset(params, socket) do
    %{time_zone: time_zone, session_modal: modal} = socket.assigns
    Event.session_form_changeset(params, time_zone, DateTime.utc_now(), running?: modal.running?)
  end

  defp handle_session_result({:ok, _events}, _params, socket) do
    message =
      if socket.assigns.session_modal.mode == :edit,
        do: "Work session updated.",
        else: "Work session added."

    {:noreply, socket |> assign(:session_modal, nil) |> put_flash(:info, message)}
  end

  defp handle_session_result({:error, :overlap}, params, socket) do
    form =
      params
      |> session_changeset(socket)
      |> Ecto.Changeset.add_error(:base, "This session overlaps with your existing events.")
      |> to_form(as: :session, action: :validate)

    {:noreply, assign(socket, :session_form, form)}
  end

  defp handle_session_result({:error, _changeset}, _params, socket) do
    {:noreply, put_flash(socket, :error, "Couldn't save the session. Please try again.")}
  end

  defp assign_status(socket, event) do
    status = Events.current_status(event)
    # Pre-select the last used location for the next session.
    location = last_location(event)

    socket
    |> assign(:current_status, status)
    |> assign(:working?, status == Event.joined())
    |> assign(:last_location, location)
    |> assign(:quick_form, to_form(%{"tags" => location}, as: :quick_event))
  end

  defp last_location(event) do
    tags = event && event.tags
    if tags in Event.tags(), do: tags, else: Event.default_tag()
  end

  # Live events are only shown if they fall inside the loaded window, so the
  # log never has gaps. Older ones show up through "load more".
  defp add_events(socket, events) do
    case ActivityLog.placement(socket.assigns.log_window, events) do
      :append -> ActivityLog.append(socket, events)
      :reload -> reload_log(socket, Enum.map(events, & &1.id))
      :ignore -> socket
    end
  end

  # Re-renders the loaded window, e.g. after an event was added in the middle.
  defp reload_log(socket, fresh_ids) do
    case ActivityLog.oldest_cursor(socket.assigns) do
      nil ->
        socket

      cursor ->
        events = Events.list_events(since: cursor, limit: nil)
        ActivityLog.reset(socket, events, fresh_ids)
    end
  end

  defp time_zone(socket) do
    case get_connect_params(socket) do
      %{"timezone" => zone} -> TimeZones.normalize(zone)
      _ -> TimeZones.default()
    end
  end

  defp local_today(socket), do: TimeZones.local_today(socket.assigns.time_zone)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
