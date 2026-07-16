defmodule Sluice.Step do
  @callback run(any()) :: any()
end
