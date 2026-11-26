defmodule EmployinWeb.AuthComponents do
  @moduledoc "Building blocks shared by the login and registration pages."
  use Phoenix.Component

  import EmployinWeb.CoreComponents, only: [spinner: 1]

  @doc "Centered card used as the shell of every unauthenticated page."
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  def auth_card(assigns) do
    ~H"""
    <div class="flex min-h-dvh items-center justify-center bg-gray-50 px-4 py-8 sm:px-6 sm:py-12 lg:px-8">
      <div class="w-full max-w-sm space-y-8 rounded-xl bg-white p-6 shadow-lg sm:max-w-md sm:p-8">
        <div class="text-center">
          <h1 class="mt-6 text-2xl font-extrabold text-gray-900 sm:text-3xl">{@title}</h1>
          <p :if={@subtitle} class="mt-3 text-sm text-gray-600">{@subtitle}</p>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Full-width primary submit button that shows a spinner and `loading_label`
  while its form is being submitted.
  """
  attr :loading_label, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  def submit_button(assigns) do
    ~H"""
    <button
      type="submit"
      class="flex w-full justify-center rounded-md bg-indigo-600 px-4 py-3 text-sm font-medium text-white shadow-sm transition hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-70"
      {@rest}
    >
      <span class="phx-submit-loading:hidden">{render_slot(@inner_block)}</span>
      <span class="hidden items-center phx-submit-loading:flex">
        <.spinner class="-ml-1 mr-2 h-4 w-4" />
        {@loading_label}
      </span>
    </button>
    """
  end
end
