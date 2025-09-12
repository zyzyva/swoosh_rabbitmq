import Config

# Configure Swoosh to use Req instead of hackney
config :swoosh, :api_client, Swoosh.ApiClient.Req
