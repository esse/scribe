# Central configuration for Scribe. Scribe is a local-first tool: it runs on the
# user's own machine with their own API keys, and everything — recordings,
# generated manuals, the database — stays in a single data directory that can be
# mounted into a Docker container. All tunables come from ENV.
module Scribe
  module_function

  def config
    @config ||= ActiveSupport::OrderedOptions.new.tap do |c|
      # --- Data directory (local-first) ---
      # Everything persistent lives here: the SQLite database, uploaded
      # recordings, extracted frames, and the generated manual files. Mount this
      # one directory into a container (`-v ./data:/data`) and you keep all state.
      c.data_dir = ENV.fetch("SCRIBE_DATA_DIR", Rails.root.join("data").to_s)

      # --- LLM provider (manual generation) ---
      # "anthropic" — the user's own Anthropic API key (hosted Claude).
      # "openai"    — the user's own OpenAI API key (hosted GPT-4o, etc.).
      # "local"     — a local llama model exposed over an OpenAI-compatible API
      #               (Ollama, llama.cpp server, LM Studio…), so nothing leaves
      #               the machine.
      # "fake"      — offline deterministic stub (dev/CI; no spend, no model).
      c.llm_provider = ENV["LLM_PROVIDER"].presence || default_llm_provider

      # Anthropic (hosted Claude).
      c.anthropic_api_key   = ENV["ANTHROPIC_API_KEY"]
      c.anthropic_base_url  = ENV.fetch("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
      c.manual_model        = ENV["ANTHROPIC_MANUAL_MODEL"].presence || "claude-sonnet-4-6"
      c.caption_model       = ENV["ANTHROPIC_CAPTION_MODEL"].presence || "claude-haiku-4-5-20251001"

      # Local llama model over an OpenAI-compatible endpoint. Ollama's default is
      # http://localhost:11434/v1; pick a vision-capable model (e.g. llava,
      # llama3.2-vision, qwen2.5-vl) so it can read the screenshots.
      c.llm_base_url   = ENV["LLM_BASE_URL"].presence || "http://localhost:11434/v1"
      c.llm_model      = ENV["LLM_MODEL"].presence || "llama3.2-vision"
      c.llm_api_key    = ENV["LLM_API_KEY"] # usually unset for local servers

      # OpenAI (hosted GPT-4o, etc.) — reuses your OPENAI_API_KEY. Use a
      # vision-capable chat model so it can read the screenshots.
      c.openai_base_url  = ENV["OPENAI_BASE_URL"].presence || "https://api.openai.com/v1"
      c.openai_llm_model = ENV["OPENAI_LLM_MODEL"].presence || "gpt-4o"

      c.max_images_per_call = ENV.fetch("CLAUDE_MAX_IMAGES", 25).to_i
      c.chunk_seconds       = ENV.fetch("CLAUDE_CHUNK_SECONDS", 600).to_i # ≈10 min (SPEC §8.5)

      # --- Transcription / STT (SPEC §9.3) ---
      # Defaults to the local Whisper CLI so audio never leaves the machine. Set
      # "deepgram"/"openai" (+ key) to use a hosted provider, or "stub" offline.
      # Tests stay on the offline stub so the suite never shells out to whisper.
      c.transcription_provider  = ENV["TRANSCRIPTION_PROVIDER"].presence || (Rails.env.test? ? "stub" : "whisper")
      c.whisper_bin             = ENV["WHISPER_BIN"].presence || "faster-whisper"
      c.deepgram_api_key        = ENV["DEEPGRAM_API_KEY"]
      c.openai_api_key          = ENV["OPENAI_API_KEY"]
      c.openai_transcribe_model = ENV.fetch("OPENAI_TRANSCRIBE_MODEL", "whisper-1")

      # --- Frames (SPEC §8.4) ---
      c.default_scene_threshold = ENV.fetch("SCENE_THRESHOLD", 0.4).to_f
      c.thumbnail_max_edge      = ENV.fetch("THUMBNAIL_MAX_EDGE", 768).to_i
      c.fallback_sample_seconds = ENV.fetch("FRAME_FALLBACK_SECONDS", 20).to_i

      # --- Retention (SPEC §14) ---
      # 0 disables automatic purging (local-first default: keep everything).
      c.raw_video_retention_days = ENV.fetch("RAW_VIDEO_RETENTION_DAYS", 0).to_i

      # --- Storage (local-first: always on disk, under the data dir) ---
      c.storage_root   = ENV.fetch("STORAGE_ROOT", File.join(c.data_dir, "storage"))
      c.signed_url_ttl = ENV.fetch("SIGNED_URL_TTL", 900).to_i # 15 min (SPEC §5)

      # --- Manual result files (SPEC §11) ---
      # When a manual completes it is also written out as plain files under the
      # data dir (manual.json + markdown/html/pdf), so results are inspectable on
      # disk and travel with the mounted folder — not locked inside the database.
      c.write_result_files = ENV.fetch("WRITE_RESULT_FILES", "true") != "false"

      # --- Exports (SPEC §12.3) ---
      # PDF rendering command (WeasyPrint). Split so "python3 -m weasyprint" works.
      c.weasyprint_cmd = ENV.fetch("WEASYPRINT_CMD", "weasyprint").split
    end
  end

  # Pick a sensible default provider from what's configured: prefer the user's
  # Anthropic key, otherwise fall back to the offline fake so dev/CI never need a
  # model. Set LLM_PROVIDER=local explicitly to use a local llama server.
  def default_llm_provider
    ENV["ANTHROPIC_API_KEY"].present? ? "anthropic" : "fake"
  end
end
