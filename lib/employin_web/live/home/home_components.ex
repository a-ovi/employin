defmodule EmployinWeb.HomeComponents do
  @moduledoc """
  Function components for the home page (`EmployinWeb.HomeLive`).

  Events reach these components as plain maps (see `HomeLive.ActivityLog`) with
  UTC times. `time_zone` (the viewer's IANA zone, from the browser) converts
  them to local time.
  """
  use EmployinWeb, :html

  alias Employin.Events.Event

  ## Layout

  attr :current_user, :map, required: true

  def app_header(assigns) do
    ~H"""
    <header class="shrink-0 bg-white shadow">
      <div class="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6 lg:px-8">
        <h1 class="text-xl font-bold text-gray-800 sm:text-2xl">Employin</h1>
        <div class="flex items-center gap-4">
          <span class="hidden text-sm text-gray-600 sm:inline">{@current_user.display_name}</span>
          <.link
            href={~p"/logout"}
            method="delete"
            class="flex items-center gap-1 font-medium text-gray-600 hover:text-gray-900"
            aria-label="Log out"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="h-5 w-5" />
            <span class="hidden sm:inline">Logout</span>
          </.link>
        </div>
      </div>
    </header>
    """
  end

  ## Activity log

  attr :log, :any, required: true, doc: "the `@streams.log` stream"
  attr :has_events?, :boolean, required: true
  attr :loader, Phoenix.LiveView.AsyncResult, required: true
  attr :more_events?, :boolean, required: true
  attr :time_zone, :string, required: true
  attr :current_user_id, :string, required: true

  def activity_log(assigns) do
    ~H"""
    <section class="relative flex min-h-0 flex-1 flex-col rounded-lg bg-white shadow">
      <div class="shrink-0 border-b border-gray-200 px-3 py-2 sm:px-6">
        <h2 class="text-base font-medium text-gray-700 sm:text-lg">Activity Log</h2>
      </div>

      <div
        id="activity-log"
        phx-hook="ActivityLog"
        data-scroll-button="scroll-to-bottom-btn"
        class="min-h-0 flex-1 overflow-y-auto"
      >
        <.async_result assign={@loader}>
          <:loading>
            <div class="flex h-full items-center justify-center gap-3 py-8 text-lg text-gray-500">
              <.spinner class="h-8 w-8 text-blue-500" /> Loading...
            </div>
          </:loading>
          <:failed>
            <div class="flex h-full items-center justify-center gap-2 py-8 text-lg text-red-500">
              <.icon name="hero-x-circle" class="h-6 w-6" /> Failed to load events.
            </div>
          </:failed>

          <div :if={!@has_events?} class="flex h-full items-center justify-center p-6">
            <p class="text-2xl font-semibold text-gray-500 sm:text-3xl">No activity yet</p>
          </div>

          <div :if={@has_events?} class="border-b py-4 text-center text-sm text-gray-500">
            <span :if={@more_events?} class="flex items-center justify-center gap-2">
              <.spinner class="h-5 w-5 text-blue-500" /> Loading more...
            </span>
            <span :if={!@more_events?}>🏁 No more events</span>
          </div>

          <ul id="events-list" phx-update="stream" class="w-full divide-y divide-gray-200">
            <%= for {dom_id, item} <- @log do %>
              <.date_divider :if={item.kind == :divider} id={dom_id} date={item.date} />
              <.event_item
                :if={item.kind == :event}
                id={dom_id}
                event={item.event}
                time_zone={@time_zone}
                editable?={item.event.user_id == @current_user_id}
              />
            <% end %>
          </ul>
        </.async_result>
      </div>

      <%!-- Outside the scroll container and ignored by LiveView, so the hook owns its visibility. --%>
      <div
        id="scroll-to-bottom"
        phx-update="ignore"
        class="pointer-events-none absolute inset-x-0 bottom-4 z-20 flex justify-center"
      >
        <button
          id="scroll-to-bottom-btn"
          type="button"
          class="pointer-events-auto hidden rounded-full bg-gray-500 p-2 text-white shadow-lg transition-colors hover:bg-gray-600"
          aria-label="Scroll to latest activity"
        >
          <.icon name="hero-arrow-down" class="h-5 w-5" />
        </button>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :date, Date, required: true

  def date_divider(assigns) do
    ~H"""
    <li id={@id} class="sticky top-0 z-10 border-b bg-gray-100 px-3 py-2 sm:px-6">
      <div class="flex items-center text-sm font-medium text-gray-500 before:mx-3 before:flex-1 before:border-b before:border-gray-200 after:mx-3 after:flex-1 after:border-b after:border-gray-200">
        {Calendar.strftime(@date, "%a, %b %d")}
      </div>
    </li>
    """
  end

  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :time_zone, :string, required: true
  attr :editable?, :boolean, default: false

  def event_item(assigns) do
    ~H"""
    <li
      id={@id}
      data-event
      phx-mounted={@event.fresh? && JS.transition("highlight-fade", time: 1500, blocking: false)}
      class="w-full px-3 py-3 transition-colors duration-300 hover:bg-gray-50 sm:px-6"
    >
      <div class="flex w-full items-center gap-2">
        <.status_dot working={joined?(@event)} />
        <div class="flex w-full flex-col overflow-hidden sm:flex-row sm:items-center">
          <span class="truncate font-medium text-gray-900 sm:mr-1">{@event.user.display_name}</span>
          <span class="truncate text-sm text-gray-500">({@event.user.email})</span>
        </div>
        <button
          :if={@editable?}
          type="button"
          phx-click="edit-session"
          phx-value-id={@event.id}
          class="shrink-0 rounded p-1 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-700"
          aria-label="Edit this work session"
          title="Edit this work session"
        >
          <.icon name="hero-pencil-square" class="h-4 w-4" />
        </button>
      </div>
      <div class="mt-1 flex w-full items-center justify-between pl-5">
        <div class="flex items-center gap-2">
          <p class="text-sm text-gray-700">
            {if joined?(@event), do: "Started work", else: "Ended work"}
          </p>
          <span
            :if={present?(@event.tags)}
            class="inline-flex items-center rounded-full border border-gray-500 bg-gray-100 px-2 py-0.5 text-xs text-gray-700"
          >
            {@event.tags}
          </span>
        </div>
        <time
          datetime={DateTime.to_iso8601(@event.time)}
          class="ml-2 shrink-0 text-xs text-gray-500 sm:text-sm"
        >
          {format_local_time(@event.time, @time_zone)}
        </time>
      </div>
    </li>
    """
  end

  ## Status card

  attr :working, :boolean, required: true
  attr :form, Phoenix.HTML.Form, required: true

  def status_card(assigns) do
    ~H"""
    <.form
      for={@form}
      id="quick-event-form"
      phx-submit="toggle-status"
      class="flex shrink-0 flex-col gap-4 rounded-lg bg-white p-3 shadow"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <.status_dot working={@working} pulse />
          <h2 class="text-lg font-medium text-gray-700">
            {if @working, do: "Currently Working", else: "Not Working"}
          </h2>
        </div>
        <div class="flex items-center gap-2">
          <label for="location-tag" class="text-sm font-medium text-gray-600">Location:</label>
          <.input
            type="select"
            id="location-tag"
            field={@form[:tags]}
            options={Event.tags()}
            disabled={@working}
            title={@working && "The location can't be changed during a running session"}
          />
        </div>
      </div>

      <div class="flex gap-1">
        <button
          type="submit"
          phx-disable-with={if @working, do: "Ending...", else: "Starting..."}
          class={[
            "flex h-12 flex-grow items-center justify-center gap-2 rounded-lg px-4 font-semibold text-white shadow transition-colors duration-200 sm:h-14",
            if(@working, do: "bg-red-500 hover:bg-red-600", else: "bg-green-500 hover:bg-green-600")
          ]}
        >
          <.icon
            name={
              if @working,
                do: "hero-arrow-right-start-on-rectangle",
                else: "hero-arrow-left-end-on-rectangle"
            }
            class="h-5 w-5"
          />
          {if @working, do: "End Work", else: "Start Work"}
        </button>
        <button
          id="add-session-btn"
          type="button"
          phx-click="show-session-modal"
          disabled={@working}
          title={
            if @working,
              do: "Past sessions can't be added during a running session",
              else: "Add a past work session"
          }
          aria-label="Add a past work session"
          class="relative flex h-12 w-14 items-center justify-center rounded-md border border-gray-300 bg-white text-gray-600 shadow-sm transition-colors duration-200 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400 sm:h-14 sm:w-16"
        >
          <.icon name="hero-clock" class="h-7 w-7" />
          <.icon name="hero-plus-circle-mini" class="absolute right-1.5 top-1.5 h-4 w-4" />
        </button>
      </div>
    </.form>
    """
  end

  ## Past session form (modal body)

  attr :form, Phoenix.HTML.Form, required: true
  attr :today, Date, required: true
  attr :running?, :boolean, default: false
  attr :editing?, :boolean, default: false

  def session_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="session-form"
      phx-change="validate-session"
      phx-submit="save-session"
      class="space-y-6"
    >
      <fieldset>
        <legend class="mb-1 font-semibold text-gray-900">Start work</legend>
        <div class="grid grid-cols-2 gap-4">
          <.input type="date" field={@form[:starting_date]} label="Date" max={@today} />
          <.input type="time" field={@form[:starting_time]} label="Time" />
        </div>
      </fieldset>

      <fieldset :if={!@running?}>
        <legend class="mb-1 font-semibold text-gray-900">End work</legend>
        <div class="grid grid-cols-2 gap-4">
          <.input type="date" field={@form[:ending_date]} label="Date" max={@today} />
          <.input type="time" field={@form[:ending_time]} label="Time" />
        </div>
      </fieldset>

      <.input type="select" field={@form[:tags]} label="Location" options={Event.tags()} />

      <.error :for={msg <- base_errors(@form)}>{msg}</.error>

      <div class="flex gap-2 pt-2">
        <button
          type="button"
          phx-click={JS.exec("data-cancel", to: "#session-modal")}
          class="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
        >
          Cancel
        </button>
        <button
          type="submit"
          phx-disable-with="Saving..."
          class="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
        >
          {if @editing?, do: "Save", else: "Create"}
        </button>
        <button
          :if={@editing?}
          id="delete-session-btn"
          type="button"
          phx-click="delete-session"
          data-confirm={
            if @running?,
              do: "Cancel the running session?",
              else: "Delete this work session?"
          }
          class="ml-auto rounded-md px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
        >
          Delete
        </button>
      </div>
    </.form>
    """
  end

  ## Helpers

  defdelegate local_date(utc_datetime, time_zone), to: Employin.TimeZones

  def format_local_time(utc_datetime, time_zone) do
    utc_datetime |> Employin.TimeZones.to_local(time_zone) |> Calendar.strftime("%I:%M %p")
  end

  defp joined?(event), do: event.type == Event.joined()

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp base_errors(form) do
    for {:base, error} <- form.errors, do: translate_error(error)
  end
end
