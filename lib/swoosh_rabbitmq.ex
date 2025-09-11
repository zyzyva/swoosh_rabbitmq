defmodule SwooshRabbitmq do
  @moduledoc """
  SwooshRabbitmq provides a Swoosh adapter for publishing emails to RabbitMQ queues.

  This library allows you to use Swoosh's standard email interface while 
  publishing messages to RabbitMQ for asynchronous processing by email services.

  ## Quick Start

      # Add to mix.exs
      {:swoosh_rabbitmq, "~> 1.0"}

      # Configure your mailer
      config :my_app, MyApp.Mailer,
        adapter: Swoosh.Adapters.RabbitMQ,
        queue: "emails",
        host: "localhost",
        service_name: "my_app"

      # Use like any Swoosh adapter
      email = 
        new()
        |> to("user@example.com")
        |> from("noreply@myapp.com")
        |> subject("Welcome!")
        |> text_body("Welcome to our service!")

      MyApp.Mailer.deliver(email)

  See `Swoosh.Adapters.RabbitMQ` for complete configuration options.
  """
end
