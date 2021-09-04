defmodule PhoenixPubsubNats.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_pubsub_nats,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      phoenix_pubsub(),
      {:gnat, "~> 1.3"}
    ]
  end

  defp phoenix_pubsub do
    if path = System.get_env("PUBSUB_PATH") do
      {:phoenix_pubsub, "~> 2.0", path: path}
    else
      {:phoenix_pubsub, "~> 2.0"}
    end
  end
end
