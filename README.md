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

### Type-Safe Email Builders (Recommended)

The library provides type-safe builders that ensure all required fields are included:

```elixir
import SwooshRabbitMQ.EmailBuilder

# Welcome email - automatically includes verification_link field
welcome_email("user@example.com", "https://app.com/verify/abc123")
|> from("noreply@myapp.com")
|> subject("Welcome to MyApp!")
|> text_body("Please verify your email by clicking the link.")
|> html_body("<h1>Welcome!</h1><p>Click to verify...</p>")
|> MyApp.Mailer.deliver()

# Password reset - automatically includes reset_link field
password_reset_email("user@example.com", "https://app.com/reset/xyz789")
|> from("noreply@myapp.com")
|> subject("Reset your password")
|> text_body("Click the link to reset your password.")
|> MyApp.Mailer.deliver()

# Magic link login - uses password_reset type with reset_link
magic_link_email("user@example.com", "https://app.com/login/token123")
|> from("noreply@myapp.com")
|> subject("Log in to MyApp")
|> text_body("Click to log in instantly.")
|> MyApp.Mailer.deliver()

# Transactional email - no special fields required
transactional_email("user@example.com")
|> from("noreply@myapp.com")
|> subject("Your order confirmation")
|> text_body("Thank you for your order!")
|> MyApp.Mailer.deliver()
```

### Manual Email Creation

You can still create emails manually, but must ensure required fields are included:

```elixir
import Swoosh.Email

# Via header
new()
|> to("user@example.com")
|> from("noreply@myapp.com")
|> subject("Welcome!")
|> text_body("Welcome to our platform!")
|> header("X-Email-Type", "welcome")
|> put_private(:verification_link, "https://app.com/verify/123")  # Required!
|> MyApp.Mailer.deliver()

# Via private field
new()
|> to("user@example.com")
|> subject("Reset your password")
|> put_private(:email_type, "password_reset")
|> put_private(:reset_link, "https://app.com/reset/456")  # Required!
|> MyApp.Mailer.deliver()
```

**Note**: The adapter validates emails before sending. Welcome emails must include `verification_link`, and password_reset emails must include `reset_link`. Using the type-safe builders prevents these errors.

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
  "verification_link": "https://app.com/verify/123",  // For welcome emails
  "reset_link": "https://app.com/reset/456",          // For password_reset emails
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

