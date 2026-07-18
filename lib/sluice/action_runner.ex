defmodule Sluice.ActionRunner do
  use GenServer, restart: :temporary

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init({caller, action}) do
    {:ok, %{}, {:continue, {caller, action}}}
  end

  @impl true
  def handle_continue({caller, {module, input}}, _state) do
    output = module.run(input)
    send(caller, {:output, self(), output})
    {:stop, :normal, %{}}
  end
end
