defmodule Sluice.Supervisor do
  use DynamicSupervisor

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_instance(module, init_arg) do
    DynamicSupervisor.start_child(Sluice.Supervisor, {Sluice.Server, {module, init_arg}})
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
