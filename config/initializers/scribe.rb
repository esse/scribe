# Central configuration for Scribe. All secrets and tunables come from ENV so
# nothing sensitive is hardcoded and model ids stay config, not constants
# (SPEC §5, §9.1, §9.4, §13).
module Scribe
  module_function

  def config
    @config ||= ActiveSupport::OrderedOptions.new.tap do |c|
      # --- AI (SPEC §9.1) ---
      c.anthropic_api_key   = ENV["ANTHROPIC_API_KEY"]
      c.anthropic_base_url  = ENV.fetch("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
      # Vision-capable Sonnet for generation; cheaper Haiku for bulk captioning.
      c.manual_model        = ENV.fetch("ANTHROPIC_MANUAL_MODEL", "claude-sonnet-4-6")
      c.caption_model       = ENV.fetch("ANTHROPIC_CAPTION_MODEL", "claude-haiku-4-5-20251001")
      c.max_images_per_call = ENV.fetch("CLAUDE_MAX_IMAGES", 25).to_i
      c.chunk_seconds       = ENV.fetch("CLAUDE_CHUNK_SECONDS", 600).to_i # ≈10 min (SPEC §8.5)

      # --- Transcription (SPEC §9.3) ---
      # DECISION (STT provider): default to the offline stub so dev/CI never spend.
      # Set to "deepgram" (+ DEEPGRAM_API_KEY) or "whisper" in real environments.
      # TODO(decision): confirm hosted (Deepgram/AssemblyAI) vs self-hosted faster-whisper.
      c.transcription_provider = ENV.fetch("TRANSCRIPTION_PROVIDER", "stub")
      c.deepgram_api_key       = ENV["DEEPGRAM_API_KEY"]

      # --- Frames (SPEC §8.4) ---
      c.default_scene_threshold = ENV.fetch("SCENE_THRESHOLD", 0.4).to_f
      c.thumbnail_max_edge      = ENV.fetch("THUMBNAIL_MAX_EDGE", 768).to_i
      c.fallback_sample_seconds = ENV.fetch("FRAME_FALLBACK_SECONDS", 20).to_i

      # --- Credits / metering (SPEC §13.3) ---
      # TODO(decision): confirm CREDITS_PER_MINUTE and pack pricing.
      c.credits_per_minute = ENV.fetch("CREDITS_PER_MINUTE", 1).to_i

      # --- Retention (SPEC §14) ---
      # TODO(decision): confirm raw-video purge window. Default: 30 days.
      c.raw_video_retention_days = ENV.fetch("RAW_VIDEO_RETENTION_DAYS", 30).to_i

      # --- Object storage (SPEC §4, §5) ---
      # Adapter: "disk" (dev/test/CI) or "s3" (R2/MinIO/S3 in real envs).
      c.storage_adapter   = ENV.fetch("STORAGE_ADAPTER", Rails.env.production? ? "s3" : "disk")
      c.storage_bucket    = ENV.fetch("STORAGE_BUCKET", "scribe")
      c.storage_root      = ENV.fetch("STORAGE_ROOT", Rails.root.join("tmp/storage").to_s)
      c.s3_endpoint       = ENV["S3_ENDPOINT"]          # e.g. R2 endpoint or MinIO
      c.s3_region         = ENV.fetch("S3_REGION", "auto")
      c.s3_access_key_id  = ENV["S3_ACCESS_KEY_ID"]
      c.s3_secret_access_key = ENV["S3_SECRET_ACCESS_KEY"]
      c.signed_url_ttl    = ENV.fetch("SIGNED_URL_TTL", 900).to_i # 15 min (SPEC §5, §14)

      # --- Stripe (SPEC §12) ---
      c.stripe_secret_key      = ENV["STRIPE_SECRET_KEY"]
      c.stripe_webhook_secret  = ENV["STRIPE_WEBHOOK_SECRET"]
      c.stripe_success_url     = ENV.fetch("STRIPE_SUCCESS_URL", "http://localhost:3000/credits?status=success")
      c.stripe_cancel_url      = ENV.fetch("STRIPE_CANCEL_URL", "http://localhost:3000/credits?status=cancel")

      # --- Exports (SPEC §12.3) ---
      # DECISION (export billing): default built-in exports cost 0 credits; per-format
      # cost is configurable so premium formats can be charged later.
      c.export_credit_costs = { "markdown" => 0, "html" => 0, "pdf" => 0 }
    end
  end
end

# Configure the Stripe gem if a key is present (kept lazy so dev/CI boot without it).
if Scribe.config.stripe_secret_key.present?
  require "stripe"
  Stripe.api_key = Scribe.config.stripe_secret_key
end
