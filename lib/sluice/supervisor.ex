defmodule Sluice.Supervisor do
  use DynamicSupervisor

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_instance(module, init_arg) do
    with {:ok, instance} <-
           DynamicSupervisor.start_child(Sluice.Supervisor, {DynamicSupervisor, strategy: :one_for_one}),
         {:ok, step_sup} <-
           DynamicSupervisor.start_child(instance, {DynamicSupervisor, strategy: :one_for_one}),
         {:ok, _server} <-
           DynamicSupervisor.start_child(instance, {Sluice.Server, {module, step_sup, init_arg}}) do
      {:ok, instance}
    end
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
