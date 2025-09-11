defmodule SwooshRabbitmq.MixProject do
  use Mix.Project

  def project do
    [
      app: :swoosh_rabbitmq,
      version: "1.0.0",
      elixir: "~> 1.18",
      description: "Swoosh adapter for RabbitMQ message publishing",
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:swoosh, "~> 1.5"},
      {:req, "~> 0.4"},
      {:mock, "~> 0.3", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "swoosh_rabbitmq",
      description: "Swoosh adapter for publishing emails to RabbitMQ queues",
      licenses: ["MIT"],
      maintainers: ["Your Name"],
      links: %{
        "GitHub" => "https://github.com/your-org/swoosh_rabbitmq"
      },
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*)
    ]
  end
end
