defmodule Sluice.Engine.StepRunner do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init({caller, step, input}) do
    {:ok, %{}, {:continue, {caller, step, input}}}
  end

  @impl true
  def handle_continue({caller, step, input}, _state) do
    output = step.run(input)
    send(caller, {:output, output})
    {:stop, :normal, %{}}
  end
end
