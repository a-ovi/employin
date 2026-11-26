defmodule EmployinWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use EmployinWeb, :controller` and
  `use EmployinWeb, :live_view`.
  """
  use EmployinWeb, :html

  embed_templates "layouts/*"

  @doc "Top bar of the signed-in pages: app name, navigation and logout."
  attr :current_user, :map, required: true
  attr :active, :atom, values: [:activity, :reports], required: true

  def app_header(assigns) do
    ~H"""
    <header class="shrink-0 bg-white shadow">
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-3 sm:px-6 lg:px-8">
        <h1 class="text-xl font-bold text-gray-800 sm:text-2xl">Employin</h1>
        <nav class="flex items-center gap-1 text-sm font-medium" aria-label="Main">
          <.nav_link navigate={~p"/"} active={@active == :activity} icon="hero-clock">
            Activity
          </.nav_link>
          <.nav_link navigate={~p"/reports"} active={@active == :reports} icon="hero-chart-bar">
            Reports
          </.nav_link>
        </nav>
        <div class="flex items-center gap-4">
          <span class="hidden text-sm text-gray-600 md:inline">{@current_user.display_name}</span>
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

  attr :navigate, :string, required: true
  attr :active, :boolean, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "flex items-center gap-1 rounded-md px-2.5 py-1.5 transition-colors",
        if(@active,
          do: "bg-indigo-50 text-indigo-700",
          else: "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
        )
      ]}
    >
      <.icon name={@icon} class="h-4 w-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
