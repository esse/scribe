require "test_helper"

class LLMTest < ActiveSupport::TestCase
  test "factory selects a client per provider" do
    assert_instance_of Anthropic::Client, LLM.client(provider: "anthropic")
    assert_instance_of LLM::OpenaiClient, LLM.client(provider: "openai")
    assert_instance_of LLM::LocalClient, LLM.client(provider: "local")
    assert_instance_of Anthropic::FakeClient, LLM.client(provider: "fake")
    assert_raises(LLM::Error) { LLM.client(provider: "nope") }
  end

  test "model id depends on provider" do
    assert_equal Scribe.config.llm_model, LLM.model(provider: "local")
    assert_equal Scribe.config.openai_llm_model, LLM.model(provider: "openai")
    assert_equal Scribe.config.manual_model, LLM.model(provider: "anthropic")
  end

  # A LocalClient whose HTTP call is stubbed with a canned OpenAI-compatible
  # response, so we can assert the translation to the Anthropic shape.
  class StubbedLocalClient < LLM::LocalClient
    attr_reader :sent_body

    def initialize(canned)
      super()
      @canned = canned
    end

    private

    def post(_path, body)
      @sent_body = body
      @canned
    end
  end

  # Same stubbing for the OpenAI client so we can inspect the request it builds.
  class StubbedOpenaiClient < LLM::OpenaiClient
    attr_reader :sent_body

    def initialize(canned)
      super()
      @canned = canned
    end

    private

    def post(_path, body)
      @sent_body = body
      @canned
    end
  end

  # OpenAI's current hosted models reject `max_tokens`; local OpenAI-compatible
  # servers only understand `max_tokens`. Each client must send the key its
  # endpoint accepts, or manual generation fails with a 400.
  test "sends max_tokens to local servers and max_completion_tokens to OpenAI" do
    canned = { "usage" => {}, "choices" => [ { "message" => { "content" => "{}" } } ] }

    local = StubbedLocalClient.new(canned)
    local.create_message(model: "m", system: "s", messages: [], max_tokens: 1234)
    assert_equal 1234, local.sent_body[:max_tokens]
    assert_nil local.sent_body[:max_completion_tokens]

    openai = StubbedOpenaiClient.new(canned)
    openai.create_message(model: "m", system: "s", messages: [], max_tokens: 1234)
    assert_equal 1234, openai.sent_body[:max_completion_tokens]
    assert_nil openai.sent_body[:max_tokens]
  end

  test "translates an OpenAI tool call into the Anthropic tool_use shape" do
    canned = {
      "model" => "llama3.2-vision",
      "usage" => { "prompt_tokens" => 11, "completion_tokens" => 22 },
      "choices" => [ {
        "message" => {
          "tool_calls" => [ {
            "function" => { "name" => "emit_manual", "arguments" => { "title" => "T", "steps" => [] }.to_json }
          } ]
        }
      } ]
    }
    client = StubbedLocalClient.new(canned)

    response = client.create_message(
      model: "llama3.2-vision",
      system: "sys",
      messages: [ { role: "user", content: [ { type: "text", text: "hi" }, { type: "image", source: { media_type: "image/png", data: "AAAA" } } ] } ],
      tools: [ { name: "emit_manual", description: "d", input_schema: { type: "object" } } ],
      tool_choice: { type: "tool", name: "emit_manual" }
    )

    # Anthropic-shaped result the generator can parse.
    input = Anthropic::Client.tool_input(response, "emit_manual")
    assert_equal "T", input["title"]
    assert_equal({ input: 11, output: 22 }, Anthropic::Client.token_usage(response))

    # The request was translated to OpenAI format (system message + image_url).
    roles = client.sent_body[:messages].map { |m| m[:role] }
    assert_equal %w[system user], roles
    image = client.sent_body[:messages].last[:content].find { |b| b[:type] == "image_url" }
    assert_match %r{\Adata:image/png;base64,}, image[:image_url][:url]
    assert_equal "function", client.sent_body[:tool_choice][:type]
  end

  test "falls back to parsing plain JSON content when no tool call is returned" do
    canned = {
      "usage" => {},
      "choices" => [ { "message" => { "content" => "```json\n{\"title\":\"Plain\"}\n```" } } ]
    }
    response = StubbedLocalClient.new(canned).create_message(
      model: "m", system: "s", messages: [], tools: [ { name: "emit_manual" } ]
    )
    assert_equal "Plain", Anthropic::Client.tool_input(response, "emit_manual")["title"]
  end
end
