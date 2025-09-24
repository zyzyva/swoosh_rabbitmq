defmodule SwooshRabbitMQ.EmailBuilderTest do
  use ExUnit.Case, async: true

  alias SwooshRabbitMQ.EmailBuilder
  import Swoosh.Email

  describe "welcome_email/2" do
    test "creates email with welcome type and link" do
      email = EmailBuilder.welcome_email("user@example.com", "https://example.com/verify")

      assert email.to == [{"", "user@example.com"}]
      assert email.private[:email_type] == "welcome"
      assert email.private[:link] == "https://example.com/verify"
    end

    test "can be composed with other email functions" do
      email =
        EmailBuilder.welcome_email("user@example.com", "https://example.com/verify")
        |> from("noreply@app.com")
        |> subject("Welcome!")
        |> text_body("Hello")

      assert email.from == {"", "noreply@app.com"}
      assert email.subject == "Welcome!"
      assert email.text_body == "Hello"
      assert email.private[:email_type] == "welcome"
      assert email.private[:link] == "https://example.com/verify"
    end
  end

  describe "password_reset_email/2" do
    test "creates email with password_reset type and link" do
      email = EmailBuilder.password_reset_email("user@example.com", "https://example.com/reset")

      assert email.to == [{"", "user@example.com"}]
      assert email.private[:email_type] == "password_reset"
      assert email.private[:link] == "https://example.com/reset"
    end
  end

  describe "magic_link_email/2" do
    test "creates email with password_reset type and link" do
      email = EmailBuilder.magic_link_email("user@example.com", "https://example.com/login")

      assert email.to == [{"", "user@example.com"}]
      assert email.private[:email_type] == "password_reset"
      assert email.private[:link] == "https://example.com/login"
    end
  end

  describe "transactional_email/1" do
    test "creates email with transactional type" do
      email = EmailBuilder.transactional_email("user@example.com")

      assert email.to == [{"", "user@example.com"}]
      assert email.private[:email_type] == "transactional"
      refute Map.has_key?(email.private, :link)
    end
  end

  describe "set_email_type/2" do
    test "sets email type on existing email" do
      email =
        new()
        |> to("user@example.com")
        |> EmailBuilder.set_email_type("welcome")

      assert email.private[:email_type] == "welcome"
    end

    test "only accepts valid types" do
      assert_raise FunctionClauseError, fn ->
        new()
        |> to("user@example.com")
        |> EmailBuilder.set_email_type("invalid_type")
      end
    end
  end

  describe "add_link/2" do
    test "adds link to email" do
      email =
        new()
        |> to("user@example.com")
        |> EmailBuilder.add_link("https://example.com/verify")

      assert email.private[:link] == "https://example.com/verify"
    end
  end

  describe "validate_email/1" do
    test "validates welcome email with link" do
      email = EmailBuilder.welcome_email("user@example.com", "https://example.com/verify")
      assert {:ok, ^email} = EmailBuilder.validate_email(email)
    end

    test "fails validation for welcome email without link" do
      email =
        new()
        |> to("user@example.com")
        |> EmailBuilder.set_email_type("welcome")

      assert {:error, "welcome email missing required field: link"} =
        EmailBuilder.validate_email(email)
    end

    test "validates password_reset email with link" do
      email = EmailBuilder.password_reset_email("user@example.com", "https://example.com/reset")
      assert {:ok, ^email} = EmailBuilder.validate_email(email)
    end

    test "fails validation for password_reset email without link" do
      email =
        new()
        |> to("user@example.com")
        |> EmailBuilder.set_email_type("password_reset")

      assert {:error, "password_reset email missing required field: link"} =
        EmailBuilder.validate_email(email)
    end

    test "validates transactional email without special fields" do
      email = EmailBuilder.transactional_email("user@example.com")
      assert {:ok, ^email} = EmailBuilder.validate_email(email)
    end

    test "validates email with no type specified" do
      email = new() |> to("user@example.com")
      assert {:ok, ^email} = EmailBuilder.validate_email(email)
    end
  end
end