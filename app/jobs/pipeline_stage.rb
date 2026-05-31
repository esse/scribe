# Shared behaviour for the linear pipeline jobs (SPEC §8.1): load the recording,
# run the stage idempotently, and on failure record status/failed_stage/error,
# void the credit hold, and report to Sentry. Each stage breadcrumbs its
# transition for observability (SPEC §15).
module PipelineStage
  extend ActiveSupport::Concern

  private

  # Run a stage body with uniform failure handling.
  #   stage: the Recording#failed_stage symbol used if this blows up.
  def run_stage(recording, stage:)
    breadcrumb(recording, stage)
    yield
  rescue StandardError => e
    handle_stage_failure(recording, stage, e)
  end

  def handle_stage_failure(recording, stage, error)
    Credits::Ledger.void!(recording.credit_hold)
    recording.fail!(stage:, error:)
    report(error, recording:, stage:)
  end

  def breadcrumb(recording, stage)
    Rails.logger.info(tag: "pipeline", recording_id: recording.id, stage:)
    Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: "pipeline", message: stage.to_s, data: { recording_id: recording.id })) if defined?(Sentry) && Sentry.initialized?
  end

  def report(error, **context)
    Sentry.capture_exception(error, extra: context) if defined?(Sentry) && Sentry.initialized?
  end

  # Download the recording's source video to a temp path for ffmpeg work.
  def with_source_video(recording)
    Dir.mktmpdir("scribe") do |dir|
      path = File.join(dir, "input#{File.extname(recording.storage_key.to_s).presence || '.webm'}")
      Storage.download_to(recording.storage_key, path)
      yield path, dir
    end
  end
end
