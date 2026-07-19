defmodule Sluice.MixProject do
  use Mix.Project

  def project do
    [
      app: :sluice,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: "A lightweight Elixir library for building pattern-matching action pipelines.",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/corben2/sluice"}
      ],
      docs: docs(),
      deps: deps()
    ]
  end

  defp docs do
    [
      main: "Sluice",
      source_url: "https://github.com/corben2/sluice"
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.4", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
