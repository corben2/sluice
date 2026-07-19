defmodule Sluice.Action do
  @callback run(any()) :: any()

  def run(action_sup, action) do
    DynamicSupervisor.start_child(action_sup, {Sluice.ActionRunner, {self(), action}})
  end
end
