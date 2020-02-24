defmodule VistaStorage.MixProject do
  use Mix.Project

  def project do
    [
      app: :vista_storage,
      version: "0.2.0",
      elixirc_paths: elixirc_paths(Mix.env),
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
    ]
  end

  defp elixirc_paths(:test), do: ["lib","test/support"]
  defp elixirc_paths(:dev),  do: ["lib","test/support"] # <-- for test/mocks that can be activated in config/dev.exs
  defp elixirc_paths(_),     do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VistaStorage.Application, []}
    ]
  end

  def description do
    """
    A self-preloading cache keeping track of sessiosn, cinemas and films. Will
    take care of loading, expiring and via adjusted polling frequencies - the
    nearer an event, the higher the frequency.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "test"],
      maintainers: ["Martin Dobberstein (Gutsch)"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/gutschilla/elixir-vista-storage"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:vista_client, "~> 0.2"},
      {:quantum, "~> 2.3"},
    ]
  end
end
