defmodule Sluice.Server do
  use GenServer, restart: :temporary

  @opaque state :: %__MODULE__{
            sluice: module(),
            action_sup: pid(),
            user_state: any(),
            monitored: %{pid() => {reference(), Sluice.step()}},
            running_tags: %{any() => pid()}
          }

  defstruct [:sluice, :action_sup, :user_state, :monitored, :running_tags]

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init({sluice, init_arg}) do
    case sluice.init(init_arg) do
      {:next, steps, user_state} ->
        {:ok, action_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

        state = %__MODULE__{
          sluice: sluice,
          action_sup: action_sup,
          user_state: user_state,
          monitored: %{},
          running_tags: %{}
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
      {{ref, step}, new_state} ->
        {tag, action, input} = step
        new_state = untrack_action(new_state, from, tag)

        emit_event([:sluice, :step, :output], %{}, %{
          sluice: state.sluice,
          tag: tag,
          output: output,
          action: action,
          input: input
        })

        Process.demonitor(ref)
        handle_output({tag, output}, new_state)

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case pop_in(state.monitored[pid]) do
      {{^ref, step}, new_state} ->
        {tag, action, input} = step
        new_state = untrack_action(new_state, pid, tag)

        emit_event([:sluice, :step, :exception], %{}, %{
          sluice: state.sluice,
          tag: tag,
          action: action,
          input: input,
          reason: reason
        })

        Process.demonitor(ref)
        handle_output({tag, {:exception, reason}}, new_state)

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
        validate_and_run_actions(steps, %{state | user_state: user_state})

      {:next, step, user_state} ->
        run_action(step, %{state | user_state: user_state})
    end
  end

  defp validate_and_run_actions(steps, state) do
    case validate_step_tags(steps, state.running_tags) do
      :ok -> run_actions(steps, state)
      {:error, reason} -> {:stop, {:shutdown, reason}, state}
    end
  end

  defp validate_step_tags(steps, running_tags) do
    duped =
      steps
      |> Enum.map(&elem(&1, 0))
      |> Kernel.++(Map.keys(running_tags))
      |> Enum.frequencies()
      |> Enum.find(fn _tag, count -> count > 1 end)

    case duped do
      nil ->
        :ok

      {tag, _count} ->
        {:error, {:duplicate_running_step_tag, tag}}
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

  defp start_action({tag, _action, _input}, %{running_tags: running_tags})
       when is_map_key(running_tags, tag), do: {:error, {:duplicate_running_step_tag, tag}}

  defp start_action(step, state) do
    {tag, action, input} = step

    emit_event([:sluice, :step, :start], %{}, %{
      sluice: state.sluice,
      tag: tag,
      action: action,
      input: input
    })

    case Sluice.Action.run(state.action_sup, {action, input}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        {:ok, track_action(state, pid, ref, step)}

      {:error, reason} ->
        {:error, {:failed_to_run_action, step, reason}}
    end
  end

  defp emit_event(event, measurements, metadata) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute(event, measurements, metadata)
    end
  end

  defp track_action(state, pid, ref, {tag, _action, _input} = step) do
    %{
      state
      | monitored: Map.put(state.monitored, pid, {ref, step}),
        running_tags: Map.put(state.running_tags, tag, pid)
    }
  end

  defp untrack_action(state, pid, tag) do
    %{
      state
      | monitored: Map.delete(state.monitored, pid),
        running_tags: Map.delete(state.running_tags, tag)
    }
  end
end
