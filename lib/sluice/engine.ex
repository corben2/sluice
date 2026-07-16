defmodule Sluice.Engine do
  def run(step_sup, step, input) do
    DynamicSupervisor.start_child(step_sup, {Sluice.Engine.StepRunner, {self(), step, input}})
  end
end
