defmodule Sluice.Server do
  use GenServer, restart: :temporary

  @opaque state :: %__MODULE__{
            sluice: module(),
            action_sup: pid(),
            user_state: any(),
            monitored: %{reference() => {Sluice.tag(), {module(), fun(), pos_integer()}}},
            running_tags: %{Sluice.tag() => reference()}
          }

  defstruct [:sluice, :action_sup, :user_state, :monitored, :running_tags]

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init({sluice, init_arg}) do
    case sluice.init(init_arg) do
      {:next, actions, user_state} ->
        {:ok, action_sup} = Task.Supervisor.start_link(strategy: :one_for_one)

        state = %__MODULE__{
          sluice: sluice,
          action_sup: action_sup,
          user_state: user_state,
          monitored: %{},
          running_tags: %{}
        }

        {:ok, state, {:continue, actions}}

      other ->
        other
    end
  end

  @impl true
  def handle_continue(actions, state) when is_list(actions) do
    run_actions(actions, state)
  end

  def handle_continue(action, state) do
    run_action(action, state)
  end

  @impl true
  def handle_info({ref, output}, state) do
    Process.demonitor(ref)

    case pop_in(state.monitored[ref]) do
      {nil, new_state} ->
        {:noreply, new_state}

      {action, new_state} ->
        {tag, {module, function, arity}} = action
        new_state = untrack_action(new_state, ref, tag)

        emit_event([:sluice, :action, :output], %{}, %{
          sluice: state.sluice,
          tag: tag,
          output: output,
          call: {module, function, arity}
        })

        handle_output({tag, output}, new_state)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    Process.demonitor(ref)

    case pop_in(state.monitored[ref]) do
      {nil, new_state} ->
        {:noreply, new_state}

      {action, new_state} ->
        {tag, {module, function, arity}} = action
        new_state = untrack_action(new_state, ref, tag)

        emit_event([:sluice, :action, :exception], %{}, %{
          sluice: state.sluice,
          tag: tag,
          call: {module, function, arity},
          reason: reason
        })

        handle_output({tag, {:exception, reason}}, new_state)
    end
  end

  defp handle_output(output, state) do
    case state.sluice.handle_output(output, state.user_state) do
      :stop ->
        {:stop, {:shutdown, :ok}, state}

      {:stop, result} ->
        {:stop, {:shutdown, {:ok, result}}, state}

      {:wait, user_state} ->
        {:noreply, %{state | user_state: user_state}}

      {:next, actions, user_state} when is_list(actions) ->
        validate_and_run_actions(actions, %{state | user_state: user_state})

      {:next, action, user_state} ->
        run_action(action, %{state | user_state: user_state})
    end
  end

  defp validate_and_run_actions(actions, state) do
    case validate_action_tags(actions, state.running_tags) do
      :ok -> run_actions(actions, state)
      error -> {:stop, {:shutdown, error}, state}
    end
  end

  defp validate_action_tags(actions, running_tags) do
    duped =
      actions
      |> Enum.map(&elem(&1, 0))
      |> Kernel.++(Map.keys(running_tags))
      |> Enum.frequencies()
      |> Enum.find(fn _tag, count -> count > 1 end)

    case duped do
      nil ->
        :ok

      {tag, _count} ->
        {:error, {:duplicate_running_action_tag, tag}}
    end
  end

  defp run_actions(actions, state) do
    start_result =
      Enum.reduce_while(actions, state, fn action, state ->
        case start_action(action, state) do
           {:ok, state} -> {:cont, state}
           error -> {:halt, {error, state}}
         end
       end)

    case start_result do
      {{:error, _reason} = error, state} ->
        {:stop, {:shutdown, error}, state}
      state ->
        {:noreply, state}
    end
  end

  defp run_action(action, state) do
    case start_action(action, state) do
      {:ok, state} -> {:noreply, state}
      error -> {:stop, {:shutdown, error}, state}
    end
  end

  defp start_action({tag, {_module, _function, _args}}, %{running_tags: running_tags})
       when is_map_key(running_tags, tag), do: {:error, {:duplicate_running_action_tag, tag}}

  defp start_action(action, state) do
    {tag, {module, function, args} = call} = action

    emit_event([:sluice, :action, :start], %{}, %{
      sluice: state.sluice,
      tag: tag,
      call: {module, function, length(args)}
    })

    task = Task.Supervisor.async_nolink(state.action_sup, fn -> apply(module, function, args) end)
    {:ok, track_action(state, task.ref, tag, call)}
  end

  defp emit_event(event, measurements, metadata) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute(event, measurements, metadata)
    end
  end

  defp track_action(state, ref, tag, call) do
    {module, function, args} = call

    %{
      state
      | monitored: Map.put(state.monitored, ref, {tag, {module, function, length(args)}}),
        running_tags: Map.put(state.running_tags, tag, ref)
    }
  end

  defp untrack_action(state, ref, tag) do
    %{
      state
      | monitored: Map.delete(state.monitored, ref),
        running_tags: Map.delete(state.running_tags, tag)
    }
  end
end
