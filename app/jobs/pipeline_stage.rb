# Shared behaviour for the linear pipeline jobs (SPEC §8.1, §16.7): load the
# recording, run the stage idempotently, retry transient errors a few times, and
# on a permanent (or exhausted) failure record status/failed_stage/error, void
# the credit hold, and report to Sentry. Each stage breadcrumbs its transition
# for observability (SPEC §15).
module PipelineStage
  extend ActiveSupport::Concern

  # Errors worth retrying automatically — transient infrastructure/network blips
  # rather than bad input. Wrapped in TransientError so ActiveJob's retry_on can
  # back off and try again (SPEC §16.7: "retries per stage").
  TRANSIENT_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
    Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE,
    SocketError, EOFError
  ].freeze

  # Raised to trigger an automatic retry; carries the context needed to record a
  # permanent failure once retries are exhausted.
  class TransientError < StandardError
    attr_reader :recording_id, :stage

    def initialize(recording_id:, stage:, cause:)
      @recording_id = recording_id
      @stage = stage
      super(cause.message)
      set_backtrace(cause.backtrace) if cause.backtrace
    end
  end

  included do
    # Back off and retry transient failures; record a permanent failure when the
    # attempts are used up.
    retry_on TransientError, attempts: 3, wait: :polynomially_longer do |job, error|
      job.send(:record_exhausted_failure, error)
    end
  end

  private

  # Run a stage body with uniform retry + failure handling.
  #   stage: the Recording#failed_stage symbol used if this blows up.
  def run_stage(recording, stage:)
    breadcrumb(recording, stage)
    yield
  rescue TransientError
    raise # already classified; let retry_on handle it
  rescue *TRANSIENT_ERRORS => e
    report(e, recording:, stage:, transient: true)
    raise TransientError.new(recording_id: recording.id, stage:, cause: e)
  rescue StandardError => e
    handle_stage_failure(recording, stage, e)
  end

  def handle_stage_failure(recording, stage, error)
    Credits::Ledger.void!(recording.credit_hold)
    recording.fail!(stage:, error:)
    report(error, recording:, stage:)
  end

  # Called by retry_on when transient retries are exhausted.
  def record_exhausted_failure(error)
    recording = Recording.find_by(id: error.recording_id)
    return unless recording

    handle_stage_failure(recording, error.stage, error)
  end

  def breadcrumb(recording, stage)
    Rails.logger.info(tag: "pipeline", recording_id: recording.id, stage:)
    Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: "pipeline", message: stage.to_s, data: { recording_id: recording.id })) if defined?(Sentry) && Sentry.initialized?
  end

  def report(error, **context)
    Sentry.capture_exception(error, extra: context) if defined?(Sentry) && Sentry.initialized?
  end

  # Download a recording's video to a temp path for ffmpeg work. Defaults to the
  # video the pipeline should process (the trimmed output once edits are applied,
  # otherwise the original upload); pass an explicit key to target a specific
  # object (e.g. the editor reads the pristine source).
  def with_source_video(recording, key: recording.processing_storage_key)
    Dir.mktmpdir("scribe") do |dir|
      path = File.join(dir, "input#{File.extname(key.to_s).presence || '.webm'}")
      Storage.download_to(key, path)
      yield path, dir
    end
  end
end
