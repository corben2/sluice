defmodule Sluice.Server do
  use GenServer, restart: :temporary

  @opaque state :: %__MODULE__{
            module: module(),
            action_sup: atom(),
            user_state: any(),
            monitored: %{pid() => {reference(), {module(), any()}}}
          }

  defstruct [:module, :action_sup, :user_state, :monitored]

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init({module, action_sup, init_arg}) do
    case module.init(init_arg) do
      {:next, action, user_state} ->
        state = %__MODULE__{
          module: module,
          action_sup: action_sup,
          user_state: user_state,
          monitored: %{}
        }

        {:ok, state, {:continue, action}}

      other ->
        other
    end
  end

  @impl true
  def handle_continue(action, state) do
    case Sluice.Action.run(state.action_sup, action) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        new_state = put_in(state.monitored[pid], {ref, action})
        {:noreply, new_state}
      _ ->
        {:stop, :failed_to_run_init_action, state}
    end
  end

  @impl true
  def handle_info({:output, from, output}, state) do
    case pop_in(state.monitored[from]) do
      {{ref, _action}, new_state} ->
        Process.demonitor(ref)
        handle_output(output, new_state)
      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case pop_in(state.monitored[pid]) do
      {{^ref, action}, new_state} ->
        Process.demonitor(ref)
        handle_output({:DOWN, action, reason}, new_state)
      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp handle_output(output, state) do
    case state.module.handle_output(output, state.user_state) do
      :complete ->
        {:stop, :normal, state}

      {:next, action, user_state} ->
        {:ok, pid} = Sluice.Action.run(state.action_sup, action)
        ref = Process.monitor(pid)
        new_state = put_in(state.monitored[pid], {ref, action})
        {:noreply, %{new_state | user_state: user_state}}
    end
  end
end
