defmodule Sluice.InstanceSupervisor do
  use Supervisor

  def start_link({name, module, init_arg}) do
    Supervisor.start_link(__MODULE__, {name, module, init_arg}, name: name)
  end

  def init({name, module, init_arg}) do
    step_sup_name = Module.concat(name, "StepSupervisor")
    server_name = Module.concat(name, "Server")

    children = [
      %{
        id: step_sup_name,
        start:
          {DynamicSupervisor, :start_link,
           [[name: step_sup_name, strategy: :one_for_one]]}
      },
      %{
        id: server_name,
        start:
          {Sluice.Server, :start_link,
           [{module, step_sup_name, init_arg}, [name: server_name]]},
        restart: :temporary
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
