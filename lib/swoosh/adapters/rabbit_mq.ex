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
  """

  use Swoosh.Adapter
  require Logger

  @impl Swoosh.Adapter
  def deliver(email, config \\ []) do
    rabbit_config = build_rabbit_config(config)
    message = build_message(email, config)

    case publish_message(message, rabbit_config) do
      {:ok, _response} ->
        message_id = Map.get(message, "message_id", generate_message_id())
        {:ok, %{id: message_id}}

      {:error, reason} ->
        Logger.error("Failed to publish email to RabbitMQ: #{inspect(reason)}")
        {:error, reason}
    end
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
    case Keyword.get(config, key) do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> value
      value -> String.to_integer(to_string(value))
    end
  rescue
    _ -> default
  end

  defp build_message(email, config) do
    %{
      "type" => determine_email_type(email, config),
      "to" => format_recipient(email.to),
      "subject" => email.subject,
      "body" => email.text_body || "",
      "html_body" => email.html_body,
      "from" => format_sender(email.from, config),
      "message_id" => generate_message_id(),
      "metadata" => %{
        "service" => Keyword.get(config, :service_name, "app"),
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp determine_email_type(email, config) do
    # Priority: header > private field > config default
    cond do
      header_type = get_header_value(email.headers, "x-email-type") ->
        header_type

      private_type = email.private[:email_type] ->
        to_string(private_type)

      true ->
        Keyword.get(config, :default_type, "transactional")
    end
  end

  defp get_header_value(headers, key) when is_map(headers) do
    # Case-insensitive header lookup
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(to_string(k)) == String.downcase(key) end)
    |> case do
      {_k, v} -> to_string(v)
      nil -> nil
    end
  end

  defp get_header_value(_, _), do: nil

  defp format_recipient(to) when is_list(to) do
    case to do
      [{_name, email}] -> email
      [email] when is_binary(email) -> email
      [] -> nil
    end
  end

  defp format_recipient(_), do: nil

  defp format_sender(from, config) do
    case from do
      {_name, email} -> email
      email when is_binary(email) -> email
      _ -> Keyword.get(config, :default_from, "no-reply@example.com")
    end
  end

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

    case Req.post(url, json: payload, headers: headers) do
      {:ok, %{status: 200, body: %{"routed" => true}}} ->
        Logger.debug("Successfully published email message: #{message["message_id"]}")
        {:ok, :published}

      {:ok, %{status: 200, body: %{"routed" => false}}} ->
        Logger.warning(
          "Message published but not routed (queue may not exist): #{message["message_id"]}"
        )

        {:error, "Message not routed to queue"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("RabbitMQ publish failed with status #{status}: #{inspect(body)}")
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
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
