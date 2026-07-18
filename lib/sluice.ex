defmodule Sluice do
  @moduledoc """
  Public entry point for running a Sluice workflow.

  Call `start/2` with your `Sluice` module and an initial
  argument. A per-instance supervisor (plus its runner supervisor and
  server) is started on demand under the top-level `Sluice.Supervisor`.
  """

  @callback init(init_arg :: any()) ::
              {:next, {first_step :: module(), input :: any()}, state :: any()}
              | {:stop, reason :: any()}

  @callback handle_output(output :: any(), state :: any()) ::
              {:next, {next_step :: module(), input :: any()}, state :: any()}
              | :complete

  def start(module, init_arg) do
    Sluice.Supervisor.start_instance(module, init_arg)
  end
end
