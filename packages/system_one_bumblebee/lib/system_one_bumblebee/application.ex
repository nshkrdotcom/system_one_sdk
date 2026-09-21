defmodule SystemOneBumblebee.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: SystemOneBumblebee.ServingRegistry},
      SystemOneBumblebee.ServingSupervisor
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: SystemOneBumblebee.Supervisor
    )
  end
end
