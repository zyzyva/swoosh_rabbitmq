defmodule SwooshRabbitMQ.EmailBuilder do
  @moduledoc """
  Provides type-safe builders for different email types that ensure
  all required fields are included for the email service.

  Each email type has specific requirements:
  - welcome: requires verification_link
  - password_reset: requires reset_link
  - transactional: no additional fields required
  """

  import Swoosh.Email

  @doc """
  Builds a welcome email with required verification_link field.

  ## Examples

      iex> welcome_email("user@example.com", "https://example.com/verify/123")
      ...> |> from("noreply@app.com")
      ...> |> subject("Welcome!")
      ...> |> text_body("Welcome to our app!")
  """
  def welcome_email(to_email, verification_link) when is_binary(verification_link) do
    new()
    |> to(to_email)
    |> put_private(:email_type, "welcome")
    |> put_private(:verification_link, verification_link)
  end

  @doc """
  Builds a password reset email with required reset_link field.

  ## Examples

      iex> password_reset_email("user@example.com", "https://example.com/reset/456")
      ...> |> from("noreply@app.com")
      ...> |> subject("Reset your password")
      ...> |> text_body("Click here to reset your password")
  """
  def password_reset_email(to_email, reset_link) when is_binary(reset_link) do
    new()
    |> to(to_email)
    |> put_private(:email_type, "password_reset")
    |> put_private(:reset_link, reset_link)
  end

  @doc """
  Builds a magic link login email using password_reset type with reset_link.

  ## Examples

      iex> magic_link_email("user@example.com", "https://example.com/login/789")
      ...> |> from("noreply@app.com")
      ...> |> subject("Log in to your account")
      ...> |> text_body("Click here to log in")
  """
  def magic_link_email(to_email, login_link) when is_binary(login_link) do
    new()
    |> to(to_email)
    |> put_private(:email_type, "password_reset")
    |> put_private(:reset_link, login_link)
  end

  @doc """
  Builds a transactional email (default type, no special fields required).

  ## Examples

      iex> transactional_email("user@example.com")
      ...> |> from("noreply@app.com")
      ...> |> subject("Your order confirmation")
      ...> |> text_body("Order #123 confirmed")
  """
  def transactional_email(to_email) do
    new()
    |> to(to_email)
    |> put_private(:email_type, "transactional")
  end

  @doc """
  Sets the email type explicitly. Useful for migration or custom types.
  Note: This doesn't add required fields automatically.
  """
  def set_email_type(email, type) when type in ["welcome", "password_reset", "transactional"] do
    put_private(email, :email_type, type)
  end

  @doc """
  Adds verification_link to an email (for welcome emails).
  """
  def add_verification_link(email, link) when is_binary(link) do
    put_private(email, :verification_link, link)
  end

  @doc """
  Adds reset_link to an email (for password_reset emails).
  """
  def add_reset_link(email, link) when is_binary(link) do
    put_private(email, :reset_link, link)
  end

  @doc """
  Validates that an email has all required fields for its type.
  Returns {:ok, email} or {:error, missing_fields}.

  This is called automatically by the RabbitMQ adapter before sending.
  """
  def validate_email(email) do
    case Map.get(email.private, :email_type) do
      "welcome" ->
        if Map.get(email.private, :verification_link) do
          {:ok, email}
        else
          {:error, "welcome email missing required field: verification_link"}
        end

      "password_reset" ->
        if Map.get(email.private, :reset_link) do
          {:ok, email}
        else
          {:error, "password_reset email missing required field: reset_link"}
        end

      _ ->
        # transactional or unspecified type - no special fields required
        {:ok, email}
    end
  end
end