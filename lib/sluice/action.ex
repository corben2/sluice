defmodule Sluice.Action do
  @callback run(any()) :: any()

  def run(action_sup, action) do
    {module, input} = action
    caller = self()

    execute = fn ->
      output = module.run(input)
      send(caller, {:output, self(), output})
    end

    DynamicSupervisor.start_child(action_sup, {Task, execute})
  end
end
