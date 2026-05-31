# Observability wired from milestone 0 (SPEC §4, §15). No-op without SENTRY_DSN
# so dev/CI boot cleanly; breadcrumbs for each pipeline stage are added in jobs.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1).to_f
    config.environment = Rails.env
    # Never ship request bodies that might contain signed URLs or recordings.
    config.send_default_pii = false
  end
end
