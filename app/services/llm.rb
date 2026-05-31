# LLM provider selection for manual generation. The pipeline is written against
# the Anthropic Messages shape (content blocks + a forced `tool_use` result), so
# every client returns that same shape and the generator stays provider-agnostic.
#
#   "anthropic" — the user's own Anthropic API key (hosted Claude).
#   "openai"    — the user's own OpenAI API key (hosted GPT-4o, etc.).
#   "local"     — a local llama model over an OpenAI-compatible API (Ollama,
#                 llama.cpp server, LM Studio) — nothing leaves the machine.
#   "fake"      — offline deterministic stub (dev/CI; no model, no spend).
module LLM
  class Error < StandardError; end

  module_function

  # Build the client for the configured (or overridden) provider.
  def client(provider: Scribe.config.llm_provider)
    case provider.to_s
    when "anthropic" then Anthropic::Client.new
    when "openai"    then LLM::OpenaiClient.new
    when "local"     then LLM::LocalClient.new
    when "fake", ""  then Anthropic::FakeClient.new
    else raise Error, "Unknown LLM_PROVIDER: #{provider.inspect}"
    end
  end

  # The model id to send for the configured provider.
  def model(provider: Scribe.config.llm_provider)
    case provider.to_s
    when "local"  then Scribe.config.llm_model
    when "openai" then Scribe.config.openai_llm_model
    else Scribe.config.manual_model
    end
  end
end
