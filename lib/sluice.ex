defmodule Sluice do
  @moduledoc """
  A lightweight Elixir library for building pattern-matching action pipelines.

  A "sluice" is a module that implements the `Sluice` behaviour: two
  callbacks (`c:init/1` and `c:handle_output/2`) that route actions
  based on pattern-matched outputs. Each action runs in its own
  supervised process. Call `Sluice.start/2` to run one.

  ## Quickstart

  Define an action:

      defmodule MyApp.Steps.Classify do
        @behaviour Sluice.Action

        @impl Sluice.Action
        def run(n) when is_integer(n) do
          if rem(n, 2) == 0, do: {:classify, :even, n}, else: {:classify, :odd, n}
        end
      end

      defmodule MyApp.Steps.Double do
        @behaviour Sluice.Action

        @impl Sluice.Action
        def run(n), do: {:done, n * 2}
      end

  Define a sluice:

      defmodule MyApp.Workflow do
        @behaviour Sluice

        @impl Sluice
        def init(n) when is_integer(n) do
          {:next, {MyApp.Steps.Classify, n}, %{original: n}}
        end

        @impl Sluice
        def handle_output({:classify, :odd, n}, state) do
          {:next, {MyApp.Steps.Double, n}, state}
        end

        def handle_output({:classify, :even, n}, state) do
          IO.puts("Even: \#{n}")
          :complete
        end

        def handle_output({:done, result}, state) do
          {:complete, result}
        end
      end

  Start it:

      iex> Sluice.start(MyApp.Workflow, 21)
      {:ok, 42}

  The sluice runs in a supervised process under `Sluice.Supervisor`.
  `Sluice.start/2` blocks until the sluice completes, returns a result,
  or crashes.

  ## Callbacks

  A sluice module implements two callbacks:

  * `c:init/1` - returns the first action to run
  * `c:handle_output/2` - receives each action's output and decides what
    to do next

  ### Return values

  Both callbacks return one of:

  | Return | Meaning |
  |---|---|
  | `{:next, {module, input}, state}` | Run a single action next |
  | `{:next, [{module, input}], state}` | Run multiple actions in parallel |
  | `{:wait, state}` | Wait for more outputs (for parallel fan-in) |
  | `:complete` | Stop successfully |
  | `{:complete, result}` | Stop and return a result |
  | `{:stop, reason}` | Stop with an error (`c:init/1` only) |

  ## Error handling

  When an action crashes (raises), the server sends
  `{:exception, {action_module, input}, reason}` to `c:handle_output/2`.
  You can pattern-match on it to retry, log, or give up:

      def handle_output({:exception, {Classify, n}, reason}, state) do
        Logger.error("Classify failed on \#{n}: \#{inspect(reason)}")
        {:complete, {:error, reason}}
      end

  ## Parallel actions

  Return a list of actions to run them concurrently.
  Use `:wait` and state to collect all outputs before continuing:

      def handle_output({:fetch_repos, user}, state) do
        actions = for repo <- user.repos, do: {CloneRepo, {repo, user.token}}
        {:next, actions, %{state | results: %{}, pending: length(actions)}}
      end

      def handle_output(output, %{pending: pending} = state) do
        state = %{state | results: Map.put(state.results, output.repo, output), pending: pending - 1}

        if state.pending == 0 do
          {:complete, state.results}
        else
          {:wait, state}
        end
      end

  The first clause fans out to multiple `CloneRepo` actions.
  The second handles *all* outputs that don't match a more specific
  pattern, decrementing a counter and collecting results in state.
  When every action has reported back, it completes.

  ## Telemetry

  When the optional `:telemetry` dependency is available, the
  following events are emitted:

  | Event | Metadata |
  |---|---|
  | `[:sluice, :action, :start]` | `:sluice`, `:action`, `:input` |
  | `[:sluice, :action, :output]` | `:sluice`, `:output` |
  | `[:sluice, :action, :exception]` | `:sluice`, `:action`, `:input`, `:reason` |

  Add `{:telemetry, ">= 0.0.0"}` to your own deps to enable it.

  ## Starting the supervisor

  Add `Sluice.Supervisor` to your application's supervision tree:

      children = [
        Sluice.Supervisor
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """

  @callback init(init_arg :: any()) ::
              {:next, {action :: module(), input :: any()}, state :: any()}
              | {:next, [{action :: module(), input :: any()}], state :: any()}
              | {:stop, reason :: any()}

  @callback handle_output(output :: any(), state :: any()) ::
              {:next, {action :: module(), input :: any()}, state :: any()}
              | {:next, [{action :: module(), input :: any()}], state :: any()}
              | :complete
              | {:complete, result :: any()}
              | {:wait, state :: any()}

  @doc """
  Starts a sluice and blocks until it completes.

  Returns `:ok` if the sluice completes with `:complete`,
  `{:ok, result}` for `{:complete, result}`,
  or `{:error, reason}` on failure.

  ## Examples

      iex> Sluice.start(MyWorkflow, 21)
      {:ok, 42}

      iex> Sluice.start(MyWorkflow, :bad_input)
      {:error, {:failed_to_run_action, {MyAction, :bad_input}, reason}}
  """
  @spec start(module(), any()) :: :ok | {:ok, result :: any()} | {:error, reason :: any()}
  def start(module, init_arg) do
    case Sluice.Supervisor.start_instance(module, init_arg) do
      {:ok, server} ->
        ref = Process.monitor(server)

        receive do
          {:DOWN, ^ref, :process, ^server, :shutdown} ->
            :ok

          {:DOWN, ^ref, :process, ^server, {:shutdown, {:failed_to_run_action, step, reason}}} ->
            {:error, {:failed_to_run_action, step, reason}}

          {:DOWN, ^ref, :process, ^server, {:shutdown, result}} ->
            {:ok, result}

          {:DOWN, ^ref, :process, ^server, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end