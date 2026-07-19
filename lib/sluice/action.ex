defmodule Sluice.Action do
  @moduledoc """
  Behaviour for Sluice actions.

  An action is the workhorse of a sluice. Implement `c:run/1` to
  define what the action does. The return value becomes the output
  that `c:Sluice.handle_output/2` pattern-matches on.

  ## Example

      defmodule MyApp.Steps.Classify do
        @behaviour Sluice.Action

        @impl Sluice.Action
        def run(n) when is_integer(n) do
          if rem(n, 2) == 0, do: {:classify, :even, n}, else: {:classify, :odd, n}
        end
      end

  The action's `run/1` receives the input from the action tuple
  `{MyApp.Steps.Classify, 21}` and returns an output that routes to
  the next action.
  """

  @callback run(input :: any()) :: output :: any()

  @doc false
  @spec run(pid(), {module(), any()}) :: DynamicSupervisor.on_start_child()
  def run(action_sup, action) do
    DynamicSupervisor.start_child(action_sup, {Sluice.ActionRunner, {self(), action}})
  end
end
