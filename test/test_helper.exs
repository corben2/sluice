ExUnit.start()

# Start the Sluice supervisor (handle already_started for test re-runs)
case Sluice.Supervisor.start_link([]) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end
