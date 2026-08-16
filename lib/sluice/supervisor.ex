defmodule Sluice.Supervisor do
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  def start(module, init_arg) do
    DynamicSupervisor.start_child(Sluice.Supervisor, {Sluice.Server, {module, init_arg}})
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
