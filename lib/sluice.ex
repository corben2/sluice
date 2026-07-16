defmodule Sluice do
  def start(module, init_arg) do
    DynamicSupervisor.start_child(Sluice.Supervisor, {Sluice.InstanceSupervisor, {module, init_arg}})
  end
end
