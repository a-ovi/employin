defmodule Employin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EmployinWeb.Telemetry,
      Employin.Repo,
      {DNSCluster, query: Application.get_env(:employin, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Employin.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Employin.Finch},
      # Start a worker by calling: Employin.Worker.start_link(arg)
      # {Employin.Worker, arg},
      # Start to serve requests, typically the last entry
      EmployinWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Employin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EmployinWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
