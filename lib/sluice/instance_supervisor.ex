defmodule Sluice.InstanceSupervisor do
  use Supervisor

  def start_link({name, module, init_arg}) do
    Supervisor.start_link(__MODULE__, {name, module, init_arg}, name: name)
  end

  def init({name, module, init_arg}) do
    step_sup_name = Module.concat(name, "StepSupervisor")
    server_name = Module.concat(name, "Server")

    children = [
      {DynamicSupervisor, name: step_sup_name, strategy: :one_for_one},
      {Sluice.Server, {module, step_sup_name, init_arg}, name: server_name}
    ]
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
