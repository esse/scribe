require "net/http"
require "json"
module Anthropic
  # Minimal HTTP client for the Messages API (SPEC §4 allows the official SDK or
  # plain HTTP; plain HTTP keeps the dependency surface small and tests offline).
  # Supports tool use for forced structured output (SPEC §9.2) and image blocks
  # for vision (SPEC §9.3).
  class Client
    API_VERSION = "2023-06-01"

    def initialize(api_key: Scribe.config.anthropic_api_key, base_url: Scribe.config.anthropic_base_url)
      @api_key = api_key
      @base_url = base_url
    end

    # Returns the parsed JSON response. Raises on non-200.
    def create_message(model:, system:, messages:, tools: nil, tool_choice: nil, max_tokens: 4096)
      raise "ANTHROPIC_API_KEY not set" if @api_key.blank?

      body = { model:, system:, messages:, max_tokens: }
      body[:tools] = tools if tools
      body[:tool_choice] = tool_choice if tool_choice

      uri = URI("#{@base_url}/v1/messages")
      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = @api_key
      req["anthropic-version"] = API_VERSION
      req["content-type"] = "application/json"
      req.body = body.to_json

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 600) { |h| h.request(req) }
      raise "Anthropic error #{res.code}: #{res.body}" unless res.code.to_i == 200

      JSON.parse(res.body)
    end

    # Pull the input of the first tool_use block whose name matches (SPEC §9.2).
    def self.tool_input(response, tool_name)
      block = (response["content"] || []).find { |c| c["type"] == "tool_use" && c["name"] == tool_name }
      block && block["input"]
    end

    # Sum token usage for per-job metering (SPEC §9.4).
    def self.token_usage(response)
      usage = response["usage"] || {}
      { input: usage["input_tokens"].to_i, output: usage["output_tokens"].to_i }
    end
  end
end
