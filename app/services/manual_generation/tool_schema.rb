module ManualGeneration
  # Forced structured output schema (SPEC §9.2). The tool input *is* the manual.
  module ToolSchema
    NAME = "emit_manual".freeze

    def self.definition
      {
        name: NAME,
        description: "Return the structured user manual.",
        input_schema: {
          type: "object",
          required: %w[title summary steps],
          properties: {
            title: { type: "string" },
            summary: { type: "string" },
            steps: {
              type: "array",
              items: {
                type: "object",
                required: %w[title body_markdown source_start_ms source_end_ms frame_timestamp_ms],
                properties: {
                  title: { type: "string" },
                  body_markdown: { type: "string" },
                  source_start_ms: { type: "integer" },
                  source_end_ms: { type: "integer" },
                  frame_timestamp_ms: {
                    type: "integer",
                    description: "Must be one of the supplied candidate frame timestamps."
                  }
                }
              }
            }
          }
        }
      }
    end

    SYSTEM = <<~PROMPT.freeze
      You convert a screen-recording transcript and screenshots into a clear, accurate
      step-by-step user manual. Use only what is shown or said — never invent UI. Each
      step references exactly one supplied frame timestamp (typically the frame showing
      the result of the described action). Write imperative, concise instructions.
    PROMPT
  end
end
