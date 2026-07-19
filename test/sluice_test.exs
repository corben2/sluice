defmodule SluiceTest do
  use ExUnit.Case

  # Test workflow: runs a single action that sends a message to the test process
  defmodule SendAction do
    @behaviour Sluice.Action
    def run(parent) do
      send(parent, {:action_ran, self()})
      {:done, parent}
    end
  end

  defmodule SingleStepWorkflow do
    @behaviour Sluice

    @impl Sluice
    def init(parent) do
      {:next, {SendAction, parent}, %{parent: parent}}
    end

    @impl Sluice
    def handle_output({:done, parent}, _state) do
      send(parent, {:workflow_complete, self()})
      :complete
    end
  end

  # Test workflow: multiple steps
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

  defmodule MultiStepWorkflow do
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
      send(parent, {:workflow_complete, self()})
      :complete
    end
  end

  # Test workflow: init failure
  defmodule FailInitWorkflow do
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

  # Test workflow: returns a result
  defmodule ResultAction do
    @behaviour Sluice.Action
    def run(n) do
      {:done, n * 2}
    end
  end

  defmodule ResultWorkflow do
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

  # Test workflow: action crash
  defmodule CrashAction do
    @behaviour Sluice.Action
    def run(_) do
      raise "action crashed"
    end
  end

  defmodule CrashWorkflow do
    @behaviour Sluice

    @impl Sluice
    def init(parent) do
      {:next, {CrashAction, parent}, %{parent: parent}}
    end

    @impl Sluice
    def handle_output({:DOWN, {CrashAction, _}, reason}, state) do
      send(state.parent, {:crashed, reason})
      :complete
    end
  end

  describe "start/2" do
    test "runs a single-step workflow to completion" do
      assert :ok = Sluice.start(SingleStepWorkflow, self())
      assert_receive {:action_ran, _runner_pid}
      assert_receive {:workflow_complete, _server_pid}
    end

    test "runs a multi-step workflow to completion" do
      assert :ok = Sluice.start(MultiStepWorkflow, self())
      assert_receive {:step1, _}
      assert_receive {:step2, _}
      assert_receive {:workflow_complete, _}
    end

    test "returns {:error, reason} when init fails" do
      assert {:error, :init_failed} = Sluice.start(FailInitWorkflow, self())
    end

    test "handles action crashes via handle_output" do
      assert :ok = Sluice.start(CrashWorkflow, self())
      assert_receive {:crashed, reason}
      assert {%RuntimeError{}, _stacktrace} = reason
    end

    test "returns a result from workflow" do
      assert {:ok, 42} = Sluice.start(ResultWorkflow, 21)
    end
  end

  describe "concurrent instances" do
    test "two workflows run independently" do
      parent = self()

      task1 = Task.async(fn -> Sluice.start(SingleStepWorkflow, parent) end)
      task2 = Task.async(fn -> Sluice.start(SingleStepWorkflow, parent) end)

      assert :ok = Task.await(task1)
      assert :ok = Task.await(task2)
    end
  end
end
