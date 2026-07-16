defmodule Sluice do
  @moduledoc """
  Public entry point for running a Sluice workflow.

  Call `start/2` with your `Sluice.Behaviour` module and an initial
  argument. A per-instance supervisor (plus its runner supervisor and
  server) is started on demand under the top-level `Sluice.Supervisor`.
  """

  def start(module, init_arg, opts \\ []) do
    name = Keyword.get(opts, :name, Sluice)
    spec = {Sluice.InstanceSupervisor, {name, module, init_arg}}
    DynamicSupervisor.start_child(Sluice.Supervisor, spec)
  end
end
