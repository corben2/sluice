defmodule Sluice.Supervisor do
  @moduledoc """
  Top-level supervisor for Sluice.

  Add it to your application's supervision tree:

      children = [
        Sluice.Supervisor
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Each call to `Sluice.start/2` spawns a new `Sluice.Server` under
  this supervisor.
  """

  use DynamicSupervisor

  @doc false
  @spec start_link([]) :: Supervisor.on_start()
  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  @spec start_instance(module(), any()) :: DynamicSupervisor.on_start_child()
  def start_instance(module, init_arg) do
    DynamicSupervisor.start_child(Sluice.Supervisor, {Sluice.Server, {module, init_arg}})
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
