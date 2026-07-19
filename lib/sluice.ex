defmodule Sluice do
  @moduledoc """
  Public entry point for running a Sluice workflow.

  Call `start/2` with your `Sluice` module and an initial argument.
  The workflow runs in a supervised process under `Sluice.Supervisor`.
  """

  @callback init(init_arg :: any()) ::
              {:next, {first_step :: module(), input :: any()}, state :: any()}
              | {:stop, reason :: any()}

  @callback handle_output(output :: any(), state :: any()) ::
              {:next, {next_step :: module(), input :: any()}, state :: any()}
              | :complete
              | {:complete, result :: any()}

  def start(module, init_arg) do
    case Sluice.Supervisor.start_instance(module, init_arg) do
      {:ok, server} ->
        ref = Process.monitor(server)

        receive do
          {:DOWN, ^ref, :process, ^server, :shutdown} ->
            :ok

          {:DOWN, ^ref, :process, ^server, {:shutdown, {:failed_to_run_action, action, reason}}} ->
            {:error, {:failed_to_run_action, action, reason}}

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
