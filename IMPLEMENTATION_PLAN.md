# Swoosh RabbitMQ Adapter Implementation Plan

## Project Overview
Build a Swoosh adapter that publishes emails to RabbitMQ queues using the HTTP Management API instead of AMQP client libraries. This adapter integrates with the existing email_service infrastructure and provisioner ecosystem.

## Core Requirements

### 1. HTTP-Based Publishing
- Use RabbitMQ Management API for message publishing
- Avoid AMQP client library compilation issues
- Publish to existing `emails` queue in `infrastructure` vhost
- Support authentication via HTTP Basic Auth

### 2. Integration with Provisioner
- Follow provisioner conventions for vhost and queue naming
- Support shared infrastructure pattern
- Include `.rabbitmq.json` manifest for credential provisioning
- Credentials managed externally during deployment

### 3. Email Type Pass-Through
- Accept email type from configuration or email headers
- Pass type directly to email_service (no auto-detection needed)
- Default to "transactional" if no type specified
- Support welcome, password_reset, transactional types

### 4. Message Format Compatibility
- Match email_service expected JSON message format
- Include all required fields: type, to, from, subject, body, html_body
- Add metadata for service identification and tracking
- Generate unique message IDs

## Implementation Steps

### Phase 1: Core Adapter Structure
1. **Swoosh Adapter Implementation**
   - Implement `Swoosh.Adapter` behavior
   - Create `deliver/2` function with email and config parameters
   - Handle success/error responses appropriately

2. **HTTP Client Setup**
   - Use Req HTTP client for RabbitMQ Management API calls
   - Configure authentication from adapter config
   - Handle connection errors gracefully

3. **Message Building**
   - Convert Swoosh.Email struct to email_service JSON format
   - Pass through email type from configuration or headers
   - Add service metadata and message ID generation

### Phase 2: RabbitMQ Integration
1. **HTTP API Publishing**
   - Implement `POST /api/exchanges/{vhost}/{exchange}/publish` endpoint
   - Handle routing to correct queue via exchange
   - Support message persistence and delivery confirmation

2. **Configuration Management**
   - Support standard RabbitMQ connection parameters
   - Allow credential override from environment variables
   - Provide sensible defaults for development

3. **Error Handling**
   - Map HTTP status codes to appropriate Swoosh responses
   - Log errors with sufficient detail for debugging
   - Handle network timeouts and connection failures

### Phase 3: Provisioner Integration
1. **RabbitMQ Manifest**
   - Create `.rabbitmq.json` following provisioner conventions
   - Define shared infrastructure vhost access
   - Specify minimal permissions (write-only to emails queue)

2. **Configuration Management**
   - Accept RabbitMQ credentials from environment variables
   - Provide development fallback credentials
   - Document expected environment variable format

3. **Testing Infrastructure**
   - Create test helpers that mock RabbitMQ responses
   - Implement message building tests without external dependencies
   - Add integration tests for end-to-end flow

### Phase 4: Developer Experience
1. **Igniter Integration**
   - Create igniter task for adapter setup
   - Auto-generate `.rabbitmq.json` manifest based on app name
   - Configure mailer with appropriate settings
   - Add manifest to .gitignore if needed

2. **Introspective Manifest Generation**
   - Detect current Mix project name automatically
   - Generate manifest with proper provisioner conventions
   - Support custom vhost/permissions via options
   - Validate manifest against provisioner schema

3. **Documentation & Helpers**
   - Update README with configuration examples
   - Document integration with email_service and provisioner
   - Provide troubleshooting guide
   - Include example configurations for different environments

## Technical Specifications

### Message Format
```json
{
  "type": "welcome|password_reset|transactional",
  "to": "user@example.com",
  "subject": "Email Subject",
  "body": "Plain text body",
  "html_body": "<html>HTML body</html>",
  "from": "noreply@app.com",
  "message_id": "unique_message_id",
  "metadata": {
    "service": "contacts4us",
    "created_at": "2024-01-01T12:00:00Z"
  }
}
```

### RabbitMQ Manifest (`.rabbitmq.json`)
```json
{
  "rabbitmq": {
    "vhosts": [
      {
        "name": "infrastructure",
        "shared": true,
        "description": "Shared vhost for infrastructure services communication"
      }
    ],
    "users": [
      {
        "username": "contacts4us",
        "vhosts": [
          {
            "name": "infrastructure", 
            "permissions": {
              "configure": "",
              "write": "emails",
              "read": ""
            }
          }
        ]
      }
    ]
  }
}
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

## Dependencies
- `swoosh ~> 1.5` - Email composition and adapter interface
- `req ~> 0.4` - HTTP client for Management API calls

## Success Criteria
1. **Functional**: Emails published via adapter appear in email_service queue
2. **Reliable**: Handles network failures and API errors gracefully
3. **Secure**: Uses proper authentication and follows security best practices
4. **Maintainable**: Well-tested with clear documentation and examples
5. **Simple**: Zero-config in development, environment-based config in production
6. **Integrated**: Works seamlessly with external credential deployment system

### Auto-Generated Manifest
The adapter can introspectively generate the `.rabbitmq.json` file:

```elixir
# Generate manifest for current Mix project
Swoosh.Adapters.RabbitMQ.generate_manifest()

# Generate with custom options
Swoosh.Adapters.RabbitMQ.generate_manifest(
  vhost: "infrastructure", 
  permissions: %{write: "emails", read: "", configure: ""}
)

# Igniter integration - automatically called during setup
mix swoosh.rabbitmq.install
```

**Generated `.rabbitmq.json`** (for contacts4us):
```json
{
  "rabbitmq": {
    "vhosts": [
      {
        "name": "infrastructure",
        "shared": true,
        "description": "Shared vhost for infrastructure services communication"
      }
    ],
    "users": [
      {
        "username": "contacts4us",
        "vhosts": [
          {
            "name": "infrastructure", 
            "permissions": {
              "configure": "",
              "write": "emails",
              "read": ""
            }
          }
        ]
      }
    ]
  }
}
```

## Usage Examples

### Basic Configuration
```elixir
# config/config.exs - Development
config :contacts4us, Contacts4us.Mailer,
  adapter: Swoosh.Adapters.RabbitMQ,
  service_name: "contacts4us",
  default_type: "transactional"
  # host, port, vhost, username, password come from environment variables

# config/runtime.exs - Production (credentials injected during deployment)
config :contacts4us, Contacts4us.Mailer,
  adapter: Swoosh.Adapters.RabbitMQ,
  host: System.get_env("RABBITMQ_HOST"),
  port: String.to_integer(System.get_env("RABBITMQ_MANAGEMENT_PORT") || "15672"),
  vhost: System.get_env("RABBITMQ_VHOST"),
  username: System.get_env("RABBITMQ_USERNAME"), 
  password: System.get_env("RABBITMQ_PASSWORD"),
  service_name: "contacts4us"
```

### Sending Different Email Types
```elixir
import Swoosh.Email

# Transactional email (default)
new()
|> to("user@example.com")
|> from("noreply@contacts4us.com")
|> subject("Your order confirmation")
|> text_body("Thank you for your order!")
|> Contacts4us.Mailer.deliver()

# Welcome email
new()
|> to("user@example.com") 
|> from("noreply@contacts4us.com")
|> subject("Welcome!")
|> text_body("Welcome to our platform!")
|> header("X-Email-Type", "welcome")
|> put_private(:email_type, "welcome")  # Alternative approach
|> Contacts4us.Mailer.deliver()
```

## Future Enhancements
- Support for multiple queue routing based on email type
- Batch publishing for high-volume scenarios  
- Metrics and monitoring integration
- Dead letter queue handling for failed deliveries