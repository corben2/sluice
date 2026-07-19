defmodule Sluice.MixProject do
  use Mix.Project

  def project do
    [
      app: :sluice,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.4", optional: true},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
