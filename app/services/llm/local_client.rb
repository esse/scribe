
require "net/http"
require "json"
module LLM
  # Talks to a local llama model exposed over an OpenAI-compatible chat API
  # (Ollama at http://localhost:11434/v1, llama.cpp server, LM Studio, …). It
  # accepts the Anthropic-style arguments the generator already produces and
  # returns an Anthropic-shaped response, so the rest of the pipeline doesn't
  # know or care which provider ran.
  #
  # Pick a vision-capable model (llava, llama3.2-vision, qwen2.5-vl) so it can
  # read the screenshots, and one that supports tool/function calling for the
  # structured `emit_manual` output. If the model returns plain JSON instead of a
  # tool call, we parse that too.
  class LocalClient
    def initialize(base_url: Scribe.config.llm_base_url, api_key: Scribe.config.llm_api_key, model: Scribe.config.llm_model)
      @base_url = base_url.to_s.chomp("/")
      @api_key = api_key
      @default_model = model
    end

    # Mirrors Anthropic::Client#create_message and returns the same shape:
    #   { "content" => [{ "type" => "tool_use", "name" =>, "input" => {…} }],
    #     "usage" => { "input_tokens" =>, "output_tokens" => }, "model" => }
    def create_message(model:, system:, messages:, tools: nil, tool_choice: nil, max_tokens: 4096)
      body = {
        model: model || @default_model,
        token_limit_param => max_tokens,
        messages: openai_messages(system, messages)
      }
      if tools
        body[:tools] = tools.map { |t| openai_tool(t) }
        body[:tool_choice] = openai_tool_choice(tool_choice)
      end

      response = post("/chat/completions", body)
      to_anthropic_shape(response, model || @default_model, tools)
    end

    private

    # The request key for the output-token cap. Local OpenAI-compatible servers
    # (Ollama, llama.cpp, LM Studio) expect the original `max_tokens`; OpenAI's
    # hosted API requires `max_completion_tokens` for its current models
    # (GPT-5 family, o-series), so OpenaiClient overrides this.
    def token_limit_param
      :max_tokens
    end

    # Anthropic content blocks → OpenAI message content. System prompt becomes a
    # leading system message; image blocks become data: URLs.
    def openai_messages(system, messages)
      out = []
      out << { role: "system", content: system } if system.present?
      Array(messages).each do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        out << { role:, content: openai_content(content) }
      end
      out
    end

    def openai_content(content)
      return content if content.is_a?(String)

      Array(content).map do |block|
        type = block[:type] || block["type"]
        case type
        when "text"
          { type: "text", text: block[:text] || block["text"] }
        when "image"
          source = block[:source] || block["source"] || {}
          media = source[:media_type] || source["media_type"] || "image/png"
          data  = source[:data] || source["data"]
          { type: "image_url", image_url: { url: "data:#{media};base64,#{data}" } }
        end
      end.compact
    end

    def openai_tool(tool)
      {
        type: "function",
        function: {
          name: tool[:name] || tool["name"],
          description: tool[:description] || tool["description"],
          parameters: tool[:input_schema] || tool["input_schema"]
        }
      }
    end

    def openai_tool_choice(tool_choice)
      return "auto" if tool_choice.blank?

      name = tool_choice[:name] || tool_choice["name"]
      name ? { type: "function", function: { name: } } : "auto"
    end

    # OpenAI chat-completion response → Anthropic-shaped response so the generator
    # can parse it with the same helpers it uses for Claude.
    def to_anthropic_shape(response, model, tools)
      message = response.dig("choices", 0, "message") || {}
      tool_name = (tools&.first && (tools.first[:name] || tools.first["name"]))
      input = tool_input(message) || json_from_text(message["content"]) || {}

      usage = response["usage"] || {}
      {
        "content" => [ { "type" => "tool_use", "name" => tool_name, "input" => input } ],
        "usage" => {
          "input_tokens" => usage["prompt_tokens"].to_i,
          "output_tokens" => usage["completion_tokens"].to_i
        },
        "model" => response["model"] || model
      }
    end

    def tool_input(message)
      call = Array(message["tool_calls"]).first
      args = call&.dig("function", "arguments")
      return nil if args.blank?

      args.is_a?(String) ? JSON.parse(args) : args
    rescue JSON::ParserError
      nil
    end

    # Fallback for models that ignore tools and just emit JSON (optionally fenced).
    def json_from_text(text)
      return nil if text.blank?

      stripped = text.to_s.gsub(/\A```(?:json)?\s*/, "").gsub(/```\s*\z/, "")
      JSON.parse(stripped)
    rescue JSON::ParserError
      nil
    end

    def post(path, body)
      uri = URI("#{@base_url}#{path}")
      req = Net::HTTP::Post.new(uri)
      req["content-type"] = "application/json"
      req["authorization"] = "Bearer #{@api_key}" if @api_key.present?
      req.body = body.to_json

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 600) { |h| h.request(req) }
      raise LLM::Error, "Local LLM error #{res.code}: #{res.body}" unless res.code.to_i == 200

      JSON.parse(res.body)
    end
  end
end
