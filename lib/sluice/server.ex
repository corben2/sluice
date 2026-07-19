defmodule Sluice.Server do
  use GenServer, restart: :temporary

  @compile {:no_warn_undefined, Telemetry}

  @opaque state :: %__MODULE__{
            sluice: module(),
            action_sup: pid(),
            user_state: any(),
            monitored: %{pid() => {reference(), {module(), any()}}}
          }

  defstruct [:sluice, :action_sup, :user_state, :monitored]

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init({sluice, init_arg}) do
    {:ok, action_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    case sluice.init(init_arg) do
      {:next, steps, user_state} ->
        state = %__MODULE__{
          sluice: sluice,
          action_sup: action_sup,
          user_state: user_state,
          monitored: %{}
        }

        {:ok, state, {:continue, steps}}

      other ->
        other
    end
  end

  @impl true
  def handle_continue(steps, state) when is_list(steps) do
    run_actions(steps, state)
  end

  def handle_continue(step, state) do
    run_action(step, state)
  end

  @impl true
  def handle_info({:output, from, output}, state) do
    case pop_in(state.monitored[from]) do
      {{ref, _step}, new_state} ->
        emit_event([:sluice, :action, :output], %{}, %{
          sluice: state.sluice,
          output: output
        })

        Process.demonitor(ref)
        handle_output(output, new_state)

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case pop_in(state.monitored[pid]) do
      {{^ref, step}, new_state} ->
        {action, input} = step

        emit_event([:sluice, :action, :exception], %{}, %{
          sluice: state.sluice,
          action: action,
          input: input,
          reason: reason
        })

        Process.demonitor(ref)
        handle_output({:exception, step, reason}, new_state)

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp handle_output(output, state) do
    case state.sluice.handle_output(output, state.user_state) do
      :complete ->
        {:stop, :shutdown, state}

      {:complete, result} ->
        {:stop, {:shutdown, result}, state}

      {:wait, user_state} ->
        {:noreply, %{state | user_state: user_state}}

      {:next, steps, user_state} when is_list(steps) ->
        run_actions(steps, %{state | user_state: user_state})

      {:next, step, user_state} ->
        run_action(step, %{state | user_state: user_state})
    end
  end

  defp run_actions(steps, state) do
    case Enum.reduce_while(steps, state, fn step, state ->
           case start_action(step, state) do
             {:ok, state} -> {:cont, state}
             {:error, reason} -> {:halt, {:error, reason, state}}
           end
         end) do
      {:error, reason, state} -> {:stop, {:shutdown, reason}, state}
      state -> {:noreply, state}
    end
  end

  defp run_action(step, state) do
    case start_action(step, state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason} -> {:stop, {:shutdown, reason}, state}
    end
  end

  defp start_action(step, state) do
    {action, input} = step

    emit_event([:sluice, :action, :start], %{}, %{
      sluice: state.sluice,
      action: action,
      input: input
    })

    case Sluice.Action.run(state.action_sup, step) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        {:ok, %{state | monitored: Map.put(state.monitored, pid, {ref, step})}}

      {:error, reason} ->
        {:error, {:failed_to_run_action, step, reason}}
    end
  end

  defp emit_event(event, measurements, metadata) do
    if Code.ensure_loaded?(Telemetry) do
      Telemetry.execute(event, measurements, metadata)
    end
  end
end
