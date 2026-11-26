defmodule EmployinWeb.HomeLive do
  @moduledoc """
  The main page. It has a real-time activity log of every user's events and a
  status card to start or end work. A modal adds past work sessions.

  Business rules live in `Employin.Events`. This LiveView only maps events to
  lightweight view maps and keeps the loaded window of the log, using keyset
  pagination ("load more" when the user scrolls to the top).
  """
  use EmployinWeb, :live_view

  import EmployinWeb.HomeComponents

  alias Employin.Events
  alias Employin.Events.Event
  alias Phoenix.LiveView.AsyncResult

  @per_page 30
  # Largest real-world UTC offsets are -12h and +14h.
  @max_tz_offset 14 * 60

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe()

    last_event = Events.last_event(socket.assigns.current_user.id)

    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:tz_offset, tz_offset(socket))
      |> assign(:events, [])
      |> assign(:more_events?, true)
      |> assign(:show_session_modal, false)
      |> assign_status(last_event)
      |> assign(:events_loader, AsyncResult.loading())
      |> start_async(:load_events, fn -> Events.list_events(limit: @per_page) end)

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_events, {:ok, events}, socket) do
    loaded = Enum.map(events, &to_view/1)

    socket =
      socket
      |> assign(:events, merge_events(loaded, socket.assigns.events))
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

    defaults = %{
      "starting_date" => today,
      "ending_date" => today,
      "tags" => socket.assigns.last_location
    }

    form =
      defaults
      |> Event.session_form_changeset(socket.assigns.tz_offset)
      |> to_form(as: :session)

    {:noreply, assign(socket, show_session_modal: true, session_form: form)}
  end

  def handle_event("close-session-modal", _params, socket) do
    {:noreply, assign(socket, :show_session_modal, false)}
  end

  def handle_event("validate-session", %{"session" => params}, socket) do
    form =
      params
      |> Event.session_form_changeset(socket.assigns.tz_offset)
      |> to_form(as: :session, action: :validate)

    {:noreply, assign(socket, :session_form, form)}
  end

  def handle_event("save-session", %{"session" => params}, socket) do
    %{current_user: user, tz_offset: tz_offset} = socket.assigns

    case Event.apply_session_form(params, tz_offset) do
      {:ok, session} ->
        user.id
        |> Events.create_work_session(session.starting, session.ending, session.tags)
        |> handle_session_result(params, socket)

      {:error, changeset} ->
        {:noreply, assign(socket, :session_form, to_form(changeset, as: :session))}
    end
  end

  def handle_event("load-more", _params, %{assigns: %{more_events?: false}} = socket) do
    {:reply, %{more: false}, socket}
  end

  def handle_event("load-more", _params, %{assigns: %{events: []}} = socket) do
    # Nothing loaded yet (initial load still running): let the client retry later.
    {:reply, %{more: true}, socket}
  end

  def handle_event("load-more", _params, socket) do
    [oldest | _] = socket.assigns.events
    page = Events.list_events(limit: @per_page, before: {oldest.time, oldest.id})
    more? = length(page) == @per_page

    socket =
      socket
      |> assign(:events, merge_events(Enum.map(page, &to_view/1), socket.assigns.events))
      |> assign(:more_events?, more?)

    {:reply, %{more: more?}, socket}
  end

  @impl true
  def handle_info({:new_event, %Event{} = event}, socket) do
    socket =
      if event.user_id == socket.assigns.current_user.id do
        assign_status(socket, event)
      else
        socket
      end

    {:noreply, maybe_add_event(socket, event)}
  end

  ## Helpers

  defp handle_session_result({:ok, _events}, _params, socket) do
    {:noreply,
     socket
     |> assign(:show_session_modal, false)
     |> put_flash(:info, "Work session added.")}
  end

  defp handle_session_result({:error, :overlap}, params, socket) do
    form =
      params
      |> Event.session_form_changeset(socket.assigns.tz_offset)
      |> Ecto.Changeset.add_error(:base, "This session overlaps with your existing events.")
      |> to_form(as: :session, action: :validate)

    {:noreply, assign(socket, :session_form, form)}
  end

  defp handle_session_result({:error, _changeset}, _params, socket) do
    {:noreply, put_flash(socket, :error, "Couldn't save the session. Please try again.")}
  end

  @doc false
  def to_view(%Event{} = event, fresh? \\ false) do
    %{
      id: event.id,
      user_id: event.user_id,
      type: event.type,
      tags: event.tags,
      time: event.time,
      fresh?: fresh?,
      user: %{
        display_name: event.user && event.user.display_name,
        email: event.user && event.user.email
      }
    }
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
  defp maybe_add_event(socket, event) do
    case socket.assigns.events do
      [oldest | _] = events ->
        if after_or_equal?(event, oldest) do
          assign(socket, :events, merge_events([to_view(event, true)], events))
        else
          socket
        end

      [] ->
        assign(socket, :events, [to_view(event, true)])
    end
  end

  defp after_or_equal?(event, oldest) do
    {DateTime.to_unix(event.time), event.id} >= {DateTime.to_unix(oldest.time), oldest.id}
  end

  defp merge_events(new_events, events) do
    (new_events ++ events)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{DateTime.to_unix(&1.time), &1.id})
  end

  defp tz_offset(socket) do
    case get_connect_params(socket) do
      %{"tz_offset" => offset} when is_integer(offset) and abs(offset) <= @max_tz_offset -> offset
      _ -> 0
    end
  end

  defp local_today(socket) do
    DateTime.utc_now() |> local_date(socket.assigns.tz_offset)
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
