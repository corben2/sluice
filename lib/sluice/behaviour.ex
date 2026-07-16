defmodule Sluice.Behaviour do
  @callback init(init_arg :: any()) ::
              {:ok, first_step :: module(), input :: any(), state :: any()}
              | {:stop, reason :: any()}

  @callback handle_output(output :: any(), state :: any()) ::
              {:ok, next_step :: module(), input :: any(), state :: any()}
              | :complete
end
