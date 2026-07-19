defmodule SluiceTest do
  use ExUnit.Case

  # Test sluice: runs a single action that sends a message to the test process
  defmodule SendAction do
    @behaviour Sluice.Action
    def run(parent) do
      send(parent, {:action_ran, self()})
      {:done, parent}
    end
  end

  defmodule SingleStepSluice do
    @behaviour Sluice

    @impl Sluice
    def init(parent) do
      {:next, {SendAction, parent}, %{parent: parent}}
    end

    @impl Sluice
    def handle_output({:done, parent}, _state) do
      send(parent, {:sluice_complete, self()})
      :complete
    end
  end

  # Test sluice: multiple steps
  defmodule Step1 do
    @behaviour Sluice.Action
    def run(parent) do
      send(parent, {:step1, self()})
      {:step1_done, parent}
    end
  end

  defmodule Step2 do
    @behaviour Sluice.Action
    def run(parent) do
      send(parent, {:step2, self()})
      {:step2_done, parent}
    end
  end

  defmodule MultiStepSluice do
    @behaviour Sluice

    @impl Sluice
    def init(parent) do
      {:next, {Step1, parent}, %{parent: parent}}
    end

    @impl Sluice
    def handle_output({:step1_done, parent}, state) do
      {:next, {Step2, parent}, state}
    end

    def handle_output({:step2_done, parent}, _state) do
      send(parent, {:sluice_complete, self()})
      :complete
    end
  end

  # Test sluice: init failure
  defmodule FailInitSluice do
    @behaviour Sluice

    @impl Sluice
    def init(_) do
      {:stop, :init_failed}
    end

    # Never called, but required by behaviour
    @impl Sluice
    def handle_output(_output, _state) do
      :complete
    end
  end

  # Test sluice: returns a result
  defmodule ResultAction do
    @behaviour Sluice.Action
    def run(n) do
      {:done, n * 2}
    end
  end

  defmodule ResultSluice do
    @behaviour Sluice

    @impl Sluice
    def init(n) do
      {:next, {ResultAction, n}, %{}}
    end

    @impl Sluice
    def handle_output({:done, result}, _state) do
      {:complete, result}
    end
  end

  # Test sluice: parallel actions from init
  defmodule ActionA do
    @behaviour Sluice.Action
    def run(parent) do
      send(parent, {:action_a_ran, self()})
      {:a_done, parent}
    end
  end

  defmodule ActionB do
    @behaviour Sluice.Action
    def run(parent) do
      send(parent, {:action_b_ran, self()})
      {:b_done, parent}
    end
  end

  defmodule ParallelInitSluice do
    @behaviour Sluice

    @impl Sluice
    def init(parent) do
      {:next, [{ActionA, parent}, {ActionB, parent}], %{parent: parent, results: []}}
    end

    @impl Sluice
    def handle_output(output, %{results: results} = state) do
      results = [output | results]

      if length(results) == 2 do
        send(state.parent, {:parallel_complete, self()})
        :complete
      else
        {:wait, %{state | results: results}}
      end
    end
  end

  # Test sluice: action crash
  defmodule CrashAction do
    @behaviour Sluice.Action
    def run(_) do
      raise "action crashed"
    end
  end

  defmodule CrashSluice do
    @behaviour Sluice

    @impl Sluice
    def init(parent) do
      {:next, {CrashAction, parent}, %{parent: parent}}
    end

    @impl Sluice
    def handle_output({:exception, {CrashAction, _}, reason}, state) do
      send(state.parent, {:crashed, reason})
      :complete
    end
  end

  describe "start/2" do
    test "runs a single-step sluice to completion" do
      assert :ok = Sluice.start(SingleStepSluice, self())
      assert_receive {:action_ran, _runner_pid}
      assert_receive {:sluice_complete, _server_pid}
    end

    test "runs a multi-step sluice to completion" do
      assert :ok = Sluice.start(MultiStepSluice, self())
      assert_receive {:step1, _}
      assert_receive {:step2, _}
      assert_receive {:sluice_complete, _}
    end

    test "runs parallel actions from init" do
      assert :ok = Sluice.start(ParallelInitSluice, self())
      assert_receive {:action_a_ran, _}
      assert_receive {:action_b_ran, _}
      assert_receive {:parallel_complete, _}
    end

    test "returns {:error, reason} when init fails" do
      assert {:error, :init_failed} = Sluice.start(FailInitSluice, self())
    end

    test "handles action crashes via handle_output" do
      assert :ok = Sluice.start(CrashSluice, self())
      assert_receive {:crashed, reason}
      assert {%RuntimeError{}, _stacktrace} = reason
    end

    test "returns a result from sluice" do
      assert {:ok, 42} = Sluice.start(ResultSluice, 21)
    end
  end

  describe "concurrent instances" do
    test "two sluices run independently" do
      parent = self()

      task1 = Task.async(fn -> Sluice.start(SingleStepSluice, parent) end)
      task2 = Task.async(fn -> Sluice.start(SingleStepSluice, parent) end)

      assert :ok = Task.await(task1)
      assert :ok = Task.await(task2)
    end
  end
end
