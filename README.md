# Swoosh RabbitMQ Adapter

A [Swoosh](https://github.com/swoosh/swoosh) adapter for publishing emails to RabbitMQ queues via HTTP Management API instead of delivering them directly. Perfect for asynchronous email processing with microservices.

## Features

- 📨 **Drop-in replacement** for other Swoosh adapters
- 🐰 **HTTP Management API** - uses REST API instead of AMQP client libraries
- 🔄 **Async processing** - emails are queued for background processing
- 🏷️ **Flexible email typing** - specify type via headers, private fields, or config
- 📊 **Message tracking** with unique message IDs
- ⚙️ **Environment-based config** - credentials from environment variables
- 🗂️ **Auto-manifest generation** - creates .rabbitmq.json for provisioning

## Installation

Add `swoosh_rabbitmq` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:swoosh_rabbitmq, "~> 1.0"}
  ]
end
```

**Note**: This adapter requires `swoosh ~> 1.5`, but Phoenix projects already include swoosh by default, so no additional dependency is needed in most cases.

For optimal performance, configure Swoosh to use the Req API client instead of hackney:

```elixir
# config/config.exs
config :swoosh, :api_client, Swoosh.ApiClient.Req
```

## Quick Setup

Generate the RabbitMQ manifest for your app:

```elixir
# In IEx or in a script
Swoosh.Adapters.RabbitMQ.generate_manifest()
```

This creates a `.rabbitmq.json` file that follows provisioner conventions for shared infrastructure access.

## Configuration

### Development
```elixir
# config/config.exs
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.RabbitMQ,
  service_name: "my_app",
  default_type: "transactional"
```

### Production
```elixir
# config/runtime.exs - Credentials injected during deployment
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.RabbitMQ,
  host: System.get_env("RABBITMQ_HOST"),
  port: String.to_integer(System.get_env("RABBITMQ_MANAGEMENT_PORT") || "15672"),
  vhost: System.get_env("RABBITMQ_VHOST"),
  username: System.get_env("RABBITMQ_USERNAME"), 
  password: System.get_env("RABBITMQ_PASSWORD"),
  service_name: "my_app"
```

### Configuration Options

- `:host` - RabbitMQ host (default: System.get_env("RABBITMQ_HOST") || "localhost")
- `:port` - Management API port (default: System.get_env("RABBITMQ_MANAGEMENT_PORT") || 15672)
- `:vhost` - Virtual host name (default: System.get_env("RABBITMQ_VHOST") || "infrastructure")
- `:queue` - Target queue name (default: "emails")
- `:username` - RabbitMQ username (from System.get_env("RABBITMQ_USERNAME"))
- `:password` - RabbitMQ password (from System.get_env("RABBITMQ_PASSWORD"))
- `:service_name` - Service identifier for metadata
- `:default_type` - Default email type (default: "transactional")

## Usage

### Basic Email
```elixir
import Swoosh.Email

new()
|> to("user@example.com")
|> from("noreply@myapp.com")
|> subject("Your order confirmation")
|> text_body("Thank you for your order!")
|> MyApp.Mailer.deliver()
```

### Specify Email Type
```elixir
# Via header
new()
|> to("user@example.com") 
|> from("noreply@myapp.com")
|> subject("Welcome!")
|> text_body("Welcome to our platform!")
|> header("X-Email-Type", "welcome")
|> MyApp.Mailer.deliver()

# Via private field
new()
|> to("user@example.com")
|> subject("Reset your password")
|> put_private(:email_type, "password_reset")
|> MyApp.Mailer.deliver()
```

## Message Format

Messages are published to RabbitMQ in JSON format compatible with email processing services:

```json
{
  "type": "welcome|password_reset|transactional",
  "to": "user@example.com",
  "subject": "Welcome!",
  "body": "Welcome to our service!",
  "html_body": "<h1>Welcome!</h1>",
  "from": "noreply@myapp.com",
  "message_id": "abc123...",
  "metadata": {
    "service": "my_app",
    "created_at": "2024-01-01T12:00:00Z"
  }
}
```

## Email Types

- **welcome** - Welcome/onboarding emails with verification links
- **password_reset** - Password reset emails with reset links
- **transactional** - Order confirmations, notifications, etc. (default)

Type priority: `X-Email-Type` header > `:email_type` private field > config default

## Auto-Generated Manifest

The adapter generates `.rabbitmq.json` manifests following provisioner conventions:

```elixir
# Generate with defaults
Swoosh.Adapters.RabbitMQ.generate_manifest()

# Generate with custom options
Swoosh.Adapters.RabbitMQ.generate_manifest(
  vhost: "production", 
  permissions: %{configure: "", write: "custom_queue", read: ""}
)
```

## Requirements

- Elixir 1.18+
- RabbitMQ 3.8+ with Management API enabled
- A consumer service to process the queued emails (e.g., email_service)

## License

MIT

