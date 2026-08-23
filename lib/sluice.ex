defmodule Sluice do
  @moduledoc """
  Public entry point for running a Sluice workflow.

  Call `run/2` with your `Sluice` module and an initial argument.
  The workflow runs in an independent process by default.
  """

  @type tag() :: any()
  @type call() :: mfa()
  @type action() :: {tag(), call()}

  @callback init(init_arg :: any()) ::
              {:next, action(), state :: any()}
              | {:next, [action()], state :: any()}
              | {:stop, reason :: any()}

  @callback handle_output(output :: any(), state :: any()) ::
              {:next, action(), state :: any()}
              | {:next, [action()], state :: any()}
              | :stop
              | {:stop, result :: any()}
              | {:wait, state :: any()}

  @spec run(module(), any()) ::
          :ok | {:ok, result :: any()} | {:error, {:duplicate_running_action_tag, tag()}}
  def run(module, init_arg) do
    case Sluice.Server.start({module, init_arg}) do
      {:ok, server} ->
        ref = Process.monitor(server)

        receive do
          {:DOWN, ^ref, :process, ^server, :shutdown} ->
            :ok

          {:DOWN, ^ref, :process, ^server, {:shutdown, result}} ->
            result

          {:DOWN, ^ref, :process, ^server, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
