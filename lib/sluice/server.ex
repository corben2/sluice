defmodule Sluice.Server do
  use GenServer

  @opaque state :: %__MODULE__{
            module: module(),
            step_sup: atom(),
            user_state: any()
          }

  defstruct [:module, :step_sup, :user_state]

  def start_link(args, opts) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init({module, step_sup, init_arg}) do
    case module.init(init_arg) do
      {:ok, step, input, user_state} ->
        state = %__MODULE__{
          module: module,
          step_sup: step_sup,
          user_state: user_state,
        }

        {:ok, state, {:continue, {step, input}}}

      other ->
        other
    end
  end

  @impl true
  def handle_continue({step, input}, state) do
    Sluice.Engine.run(state.step_sup, step, input)
    {:noreply, state}
  end

  @impl true
  def handle_info({:output, output}, state) do
    case state.module.handle_output(output, state.user_state) do
      :complete ->
        {:stop, :normal, state}

      {:ok, step, input, user_state} ->
        Sluice.Engine.run(state.step_sup, step, input)
        {:noreply, %{state | user_state: user_state}}
    end
  end
end
