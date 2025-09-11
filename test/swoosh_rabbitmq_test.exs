defmodule SwooshRabbitmqTest do
  use ExUnit.Case
  doctest SwooshRabbitmq
  import ExUnit.CaptureLog
  import ExUnit.CaptureIO

  alias Swoosh.Adapters.RabbitMQ
  import Swoosh.Email

  describe "email type detection" do
    test "detects type from X-Email-Type header" do
      email = new() 
        |> subject("Welcome!") 
        |> header("X-Email-Type", "welcome")
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "welcome"
    end

    test "detects type from private field" do
      email = new() 
        |> subject("Reset your password")
        |> put_private(:email_type, :password_reset)
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "password_reset"
    end

    test "uses config default type" do
      email = new() |> subject("Your order confirmation")
      config = [default_type: "transactional"]
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "transactional"
    end

    test "defaults to transactional when no type specified" do
      email = new() |> subject("Some email")
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "transactional"
    end

    test "header takes priority over private field" do
      email = new()
        |> subject("Test")
        |> header("X-Email-Type", "welcome")
        |> put_private(:email_type, :password_reset)
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "welcome"
    end

    test "header lookup is case insensitive" do
      email = new()
        |> subject("Test")
        |> header("x-email-type", "welcome")  # lowercase
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "welcome"
    end
  end

  describe "message building" do
    test "builds complete message structure" do
      email = 
        new()
        |> to("user@example.com")
        |> from("noreply@app.com")
        |> subject("Test Email")
        |> text_body("Hello world")
        |> html_body("<h1>Hello world</h1>")
        |> header("X-Email-Type", "welcome")

      config = [service_name: "test_app"]
      message = RabbitMQ.build_message_for_test(email, config)

      assert message["type"] == "welcome"
      assert message["to"] == "user@example.com"
      assert message["from"] == "noreply@app.com"
      assert message["subject"] == "Test Email"
      assert message["body"] == "Hello world"
      assert message["html_body"] == "<h1>Hello world</h1>"
      assert message["metadata"]["service"] == "test_app"
      assert is_binary(message["message_id"])
      assert is_binary(message["metadata"]["created_at"])
    end

    test "handles missing optional fields gracefully" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      
      assert message["to"] == "user@example.com"
      assert message["subject"] == "Test"
      assert message["body"] == ""
      refute Map.has_key?(message, "html_body")  # Should be filtered out
      assert message["metadata"]["service"] == "app"  # default
    end

    test "handles tuple recipients" do
      email = new() |> to({"Jane Doe", "jane@example.com"}) |> subject("Test")
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["to"] == "jane@example.com"
    end

    test "handles tuple senders" do
      email = new() |> from({"Support Team", "support@app.com"}) |> subject("Test")
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["from"] == "support@app.com"
    end

    test "uses default sender when from is missing" do
      email = new() |> subject("Test")
      config = [default_from: "default@app.com"]
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["from"] == "default@app.com"
    end
  end

  describe "deliver function" do
    import Mock

    test "successful delivery returns ok with message id" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = [service_name: "test_app"]

      # Mock successful HTTP response
      with_mock Req, [:passthrough], [
        post: fn _url, _opts -> 
          {:ok, %{status: 200, body: %{"routed" => true}}}
        end
      ] do
        capture_log(fn ->
          assert {:ok, %{id: message_id}} = RabbitMQ.deliver(email, config)
          assert is_binary(message_id)
          assert String.length(message_id) == 32  # 16 bytes encoded as hex
        end)
      end
    end

    test "failed delivery returns error" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = []

      # Mock HTTP failure
      with_mock Req, [:passthrough], [
        post: fn _url, _opts -> 
          {:ok, %{status: 401, body: %{"error" => "unauthorized"}}}
        end
      ] do
        capture_log(fn ->
          assert {:error, error_msg} = RabbitMQ.deliver(email, config)
          assert error_msg =~ "HTTP 401"
        end)
      end
    end

    test "message not routed returns error" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = []

      # Mock message published but not routed (queue doesn't exist)
      with_mock Req, [:passthrough], [
        post: fn _url, _opts -> 
          {:ok, %{status: 200, body: %{"routed" => false}}}
        end
      ] do
        capture_log(fn ->
          assert {:error, "Message not routed to queue"} = RabbitMQ.deliver(email, config)
        end)
      end
    end

    test "network error returns error" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = []

      # Mock network failure
      with_mock Req, [:passthrough], [
        post: fn _url, _opts -> 
          {:error, %{reason: :timeout}}
        end
      ] do
        capture_log(fn ->
          assert {:error, error_msg} = RabbitMQ.deliver(email, config)
          assert error_msg =~ "Request failed"
        end)
      end
    end
  end

  describe "configuration" do
    import Mock

    test "builds rabbit config with defaults" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = []

      # We can't easily test build_rabbit_config directly, but we can test it through deliver
      # Just verify it doesn't crash with empty config
      with_mock Req, [:passthrough], [
        post: fn url, _opts -> 
          # Verify the URL contains expected defaults
          assert url =~ "localhost:15672"
          assert url =~ "infrastructure"
          {:ok, %{status: 200, body: %{"routed" => true}}}
        end
      ] do
        capture_log(fn ->
          assert {:ok, _} = RabbitMQ.deliver(email, config)
        end)
      end
    end

    test "builds rabbit config with custom values" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = [
        host: "custom-host",
        port: 9999,
        vhost: "custom-vhost",
        queue: "custom-queue",
        username: "custom-user",
        password: "custom-pass"
      ]

      with_mock Req, [:passthrough], [
        post: fn url, opts -> 
          # Verify custom config is used
          assert url =~ "custom-host:9999"
          assert url =~ "custom-vhost"
          
          # Check the payload contains custom queue
          payload = opts[:json]
          assert payload["routing_key"] == "custom-queue"
          
          {:ok, %{status: 200, body: %{"routed" => true}}}
        end
      ] do
        capture_log(fn ->
          assert {:ok, _} = RabbitMQ.deliver(email, config)
        end)
      end
    end

    test "handles environment variables" do
      # Set environment variables
      System.put_env("RABBITMQ_HOST", "env-host")
      System.put_env("RABBITMQ_MANAGEMENT_PORT", "8080")
      System.put_env("RABBITMQ_VHOST", "env-vhost")

      email = new() |> to("user@example.com") |> subject("Test")
      config = []

      with_mock Req, [:passthrough], [
        post: fn url, _opts -> 
          # Verify env vars are used
          assert url =~ "env-host:8080"
          assert url =~ "env-vhost"
          {:ok, %{status: 200, body: %{"routed" => true}}}
        end
      ] do
        capture_log(fn ->
          assert {:ok, _} = RabbitMQ.deliver(email, config)
        end)
      end

      # Cleanup
      System.delete_env("RABBITMQ_HOST")
      System.delete_env("RABBITMQ_MANAGEMENT_PORT") 
      System.delete_env("RABBITMQ_VHOST")
    end
  end

  describe "edge cases and error handling" do
    import Mock

    test "handles nil email fields gracefully" do
      email = %Swoosh.Email{
        to: nil,
        from: nil,
        subject: nil,
        text_body: nil,
        html_body: nil,
        headers: nil
      }
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      
      assert message["to"] == nil
      assert message["subject"] == nil
      assert message["body"] == ""
      refute Map.has_key?(message, "html_body")  # nil values filtered out
    end

    test "handles empty recipient list" do
      email = new() |> to([]) |> subject("Test")
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["to"] == nil
    end

    test "handles invalid port configuration" do
      email = new() |> to("user@example.com") |> subject("Test")
      config = [port: "invalid"]  # String instead of integer
      
      # Should try to use the invalid value but not crash
      with_mock Req, [:passthrough], [
        post: fn url, _opts -> 
          assert url =~ ":invalid"  # Uses the invalid value as passed
          {:ok, %{status: 200, body: %{"routed" => true}}}
        end
      ] do
        capture_log(fn ->
          assert {:ok, _} = RabbitMQ.deliver(email, config)
        end)
      end
    end

    test "handles headers as nil" do
      email = new() |> subject("Test")
      # Ensure headers is nil
      email = %{email | headers: nil}
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "transactional"  # Should use default
    end

    test "handles empty headers map" do
      email = new() |> subject("Test") 
      # Set empty headers map
      email = %{email | headers: %{}}
      config = []
      
      message = RabbitMQ.build_message_for_test(email, config)
      assert message["type"] == "transactional"  # Should use default
    end
  end

  describe "manifest generation" do
    import Mock

    test "generates manifest with defaults" do
      # Mock Mix.Project.config
      with_mock Mix.Project, [:passthrough], [config: fn -> [app: :test_app] end] do
        capture_io(fn ->
          assert {:ok, ".rabbitmq.json"} = RabbitMQ.generate_manifest()
          
          # Check file was created
          assert File.exists?(".rabbitmq.json")
          
          # Verify content
          content = File.read!(".rabbitmq.json") |> JSON.decode!()
          assert content["rabbitmq"]["users"] |> hd() |> get_in(["username"]) == "test_app"
          assert content["rabbitmq"]["vhosts"] |> hd() |> get_in(["name"]) == "infrastructure"
          assert content["rabbitmq"]["users"] |> hd() |> get_in(["vhosts", Access.at(0), "permissions", "write"]) == "emails"
          
          # Cleanup
          File.rm(".rabbitmq.json")
        end)
      end
    end

    test "generates manifest with custom options" do
      with_mock Mix.Project, [:passthrough], [config: fn -> [app: :custom_app] end] do
        custom_permissions = %{"configure" => ".*", "write" => "custom", "read" => ""}
        
        capture_io(fn ->
          assert {:ok, ".rabbitmq.json"} = RabbitMQ.generate_manifest(
            vhost: "production", 
            permissions: custom_permissions
          )
          
          content = File.read!(".rabbitmq.json") |> JSON.decode!()
          assert content["rabbitmq"]["vhosts"] |> hd() |> get_in(["name"]) == "production"
          assert content["rabbitmq"]["users"] |> hd() |> get_in(["vhosts", Access.at(0), "permissions"]) == custom_permissions
          
          File.rm(".rabbitmq.json")
        end)
      end
    end
  end
end