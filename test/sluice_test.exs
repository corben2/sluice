defmodule SluiceTest do
  use ExUnit.Case
  doctest Sluice

  test "greets the world" do
    assert Sluice.hello() == :world
  end
end
