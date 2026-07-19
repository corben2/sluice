defmodule Sluice.ActionRunner do
  @moduledoc false

  use GenServer, restart: :temporary

  @doc false
  @spec start_link({pid(), {module(), any()}}) :: GenServer.on_start()
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
