defmodule Swoosh.Adapters.RabbitMQ do
  @email_service_vhost "email_service"

  @moduledoc """
  Swoosh adapter for publishing emails to RabbitMQ queues via HTTP Management API.

  This adapter publishes email messages to a RabbitMQ queue instead of delivering them directly.
  It's designed to work with email processing services that consume from RabbitMQ queues.

  ## Configuration

  The adapter can be configured with the following options:

  - `:host` - RabbitMQ host (default: System.get_env("RABBITMQ_HOST") || "localhost")
  - `:port` - Management API port (default: System.get_env("RABBITMQ_MANAGEMENT_PORT") || 15672)
  - `:queue` - Target queue name (default: "emails")
  - `:username` - RabbitMQ username (from System.get_env("RABBITMQ_USERNAME"))
  - `:password` - RabbitMQ password (from System.get_env("RABBITMQ_PASSWORD"))
  - `:service_name` - Service identifier for metadata
  - `:default_type` - Default email type (default: "transactional")

  Note: Always publishes to the "email_service" vhost - this is not configurable.

  ## Example

      # config/config.exs - Development
      config :my_app, MyApp.Mailer,
        adapter: Swoosh.Adapters.RabbitMQ,
        service_name: "my_app",
        default_type: "transactional"

      # config/runtime.exs - Production
      config :my_app, MyApp.Mailer,
        adapter: Swoosh.Adapters.RabbitMQ,
        host: System.get_env("RABBITMQ_HOST"),
        port: String.to_integer(System.get_env("RABBITMQ_MANAGEMENT_PORT") || "15672"),
        username: System.get_env("RABBITMQ_USERNAME"), 
        password: System.get_env("RABBITMQ_PASSWORD"),
        service_name: "my_app"

  ## Email Types

  Email type can be specified via:
  - `X-Email-Type` header: `|> header("X-Email-Type", "welcome")`
  - Private field: `|> put_private(:email_type, "welcome")`
  - Configuration default: `:default_type` option

  Supported types: "welcome", "password_reset", "transactional"

  ## Type-Safe Email Builders

  Use `SwooshRabbitMQ.EmailBuilder` for type-safe email creation that ensures
  all required fields are included:

      import SwooshRabbitMQ.EmailBuilder

      # Welcome email with verification_link
      welcome_email("user@example.com", "https://app.com/verify/123")
      |> from("noreply@app.com")
      |> subject("Welcome!")
      |> text_body("Please verify your email")
      |> Mailer.deliver()

      # Password reset with reset_link
      password_reset_email("user@example.com", "https://app.com/reset/456")
      |> from("noreply@app.com")
      |> subject("Reset your password")
      |> text_body("Click to reset")
      |> Mailer.deliver()
  """

  use Swoosh.Adapter
  require Logger

  @impl Swoosh.Adapter
  def deliver(email, config \\ []) do
    # Validate email has required fields
    email
    |> SwooshRabbitMQ.EmailBuilder.validate_email()
    |> do_deliver(email, config)
  end

  defp do_deliver({:ok, _validated_email}, email, config) do
    rabbit_config = build_rabbit_config(config)
    message = build_message(email, config)

    message
    |> publish_message(rabbit_config)
    |> handle_publish_result(message)
  end

  defp do_deliver({:error, validation_error}, _email, _config) do
    Logger.error("Email validation failed: #{validation_error}")
    {:error, validation_error}
  end

  defp handle_publish_result({:ok, _response}, message) do
    message_id = Map.get(message, "message_id", generate_message_id())
    {:ok, %{id: message_id}}
  end

  defp handle_publish_result({:error, reason}, _message) do
    Logger.error("Failed to publish email to RabbitMQ: #{inspect(reason)}")
    {:error, reason}
  end

  defp build_rabbit_config(config) do
    %{
      host: get_config(config, :host, System.get_env("RABBITMQ_HOST") || "localhost"),
      port:
        get_config(
          config,
          :port,
          String.to_integer(System.get_env("RABBITMQ_MANAGEMENT_PORT") || "15672")
        ),
      vhost: @email_service_vhost,
      queue: get_config(config, :queue, "emails"),
      username: get_config(config, :username, System.get_env("RABBITMQ_USERNAME") || "guest"),
      password: get_config(config, :password, System.get_env("RABBITMQ_PASSWORD") || "guest")
    }
  end

  defp get_config(config, key, default) do
    do_get_config(Keyword.get(config, key), default)
  end

  defp do_get_config(nil, default), do: default
  defp do_get_config(value, _default) when is_integer(value), do: value
  defp do_get_config(value, _default) when is_binary(value), do: value
  defp do_get_config(value, default) do
    String.to_integer(to_string(value))
  rescue
    _ -> default
  end

  defp build_message(email, config) do
    base_message = %{
      "type" => determine_email_type(email, config),
      "to" => format_recipient(email.to),
      "subject" => email.subject,
      "body" => email.text_body || "",
      "html_body" => email.html_body,
      "from" => format_sender(email.from, config),
      "from_name" => Keyword.get(config, :sender_name) || Keyword.get(config, :service_name, "Email2Email"),
      "message_id" => generate_message_id(),
      "metadata" => %{
        "service" => Keyword.get(config, :service_name, "app"),
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    base_message
    |> maybe_add_link(email.private)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp maybe_add_link(message, %{link: link}) when is_binary(link) do
    Map.put(message, "link", link)
  end

  defp maybe_add_link(message, _private), do: message

  defp determine_email_type(email, config) do
    # Priority: header > private field > config default
    determine_type_from_header(email.headers)
    || determine_type_from_private(email.private)
    || Keyword.get(config, :default_type, "transactional")
  end

  defp determine_type_from_header(headers) when is_map(headers) do
    get_header_value(headers, "x-email-type")
  end

  defp determine_type_from_header(_), do: nil

  defp determine_type_from_private(%{email_type: type}) when not is_nil(type) do
    to_string(type)
  end

  defp determine_type_from_private(_), do: nil

  defp get_header_value(headers, key) when is_map(headers) do
    # Case-insensitive header lookup
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == String.downcase(key) end)
    |> extract_header_value()
  end

  defp get_header_value(_, _), do: nil

  defp extract_header_value({_k, v}), do: to_string(v)
  defp extract_header_value(nil), do: nil

  defp format_recipient([{_name, email}]), do: email
  defp format_recipient([email]) when is_binary(email), do: email
  defp format_recipient([]), do: nil
  defp format_recipient(_), do: nil

  defp format_sender({_name, email}, _config), do: email
  defp format_sender(email, _config) when is_binary(email), do: email
  defp format_sender(_, config), do: Keyword.get(config, :default_from, "no-reply@email2.email")

  defp publish_message(message, rabbit_config) do
    # Use RabbitMQ Management API to publish message
    url =
      "http://#{rabbit_config.host}:#{rabbit_config.port}/api/exchanges/#{URI.encode(rabbit_config.vhost)}/amq.default/publish"

    # Build the publish payload according to Management API spec
    payload = %{
      "properties" => %{},
      "routing_key" => rabbit_config.queue,
      "payload" => JSON.encode!(message),
      "payload_encoding" => "string"
    }

    headers = [
      {"Authorization",
       "Basic #{Base.encode64("#{rabbit_config.username}:#{rabbit_config.password}")}"},
      {"Content-Type", "application/json"}
    ]

    Logger.debug(
      "Publishing email message to RabbitMQ queue #{rabbit_config.queue}: #{message["message_id"]}"
    )

    url
    |> Req.post(json: payload, headers: headers)
    |> handle_rabbitmq_response(message)
  end

  defp handle_rabbitmq_response({:ok, %{status: 200, body: %{"routed" => true}}}, message) do
    Logger.debug("Successfully published email message: #{message["message_id"]}")
    {:ok, :published}
  end

  defp handle_rabbitmq_response({:ok, %{status: 200, body: %{"routed" => false}}}, message) do
    Logger.warning(
      "Message published but not routed (queue may not exist): #{message["message_id"]}"
    )
    {:error, "Message not routed to queue"}
  end

  defp handle_rabbitmq_response({:ok, %{status: status, body: body}}, _message) do
    Logger.error("RabbitMQ publish failed with status #{status}: #{inspect(body)}")
    {:error, "HTTP #{status}: #{inspect(body)}"}
  end

  defp handle_rabbitmq_response({:error, reason}, _message) do
    Logger.error("HTTP request failed: #{inspect(reason)}")
    {:error, "Request failed: #{inspect(reason)}"}
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @doc """
  Generates a .rabbitmq.json manifest file for the current Mix project.

  This manifest follows provisioner conventions and defines the RabbitMQ
  resources needed for email publishing. Always generates access to the
  email_service vhost where emails are processed.

  ## Examples

      # Generate manifest for email publishing
      Swoosh.Adapters.RabbitMQ.generate_manifest()
  """
  def generate_manifest(_opts \\ []) do
    app_name = Mix.Project.config()[:app] |> to_string()

    manifest = %{
      "rabbitmq" => %{
        "vhosts" => [
          %{
            "name" => @email_service_vhost,
            "shared" => true,
            "description" => "Shared vhost for email service communication"
          }
        ],
        "users" => [
          %{
            "username" => app_name,
            "vhosts" => [
              %{
                "name" => @email_service_vhost,
                "permissions" => %{
                  "configure" => "",
                  "write" => "emails",
                  "read" => ""
                }
              }
            ]
          }
        ]
      }
    }

    file_content = JSON.encode!(manifest)
    File.write!(".rabbitmq.json", file_content)

    IO.puts("Generated .rabbitmq.json manifest for #{app_name}")
    {:ok, ".rabbitmq.json"}
  end

  # Public function for testing message building without RabbitMQ connection
  def build_message_for_test(email, config) do
    build_message(email, config)
  end
end
