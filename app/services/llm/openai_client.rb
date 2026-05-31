module LLM
  # OpenAI's hosted chat models (GPT-4o, etc.) for manual generation. OpenAI's
  # API is the same shape the LocalClient already speaks, so this is just that
  # client pointed at OpenAI with the user's key and a vision-capable model.
  class OpenaiClient < LocalClient
    def initialize(
      base_url: Scribe.config.openai_base_url,
      api_key: Scribe.config.openai_api_key,
      model: Scribe.config.openai_llm_model
    )
      super
    end
  end
end
