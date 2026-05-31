# Retention: auto-purge raw videos past the retention window while keeping the
# generated manuals (SPEC §14). Scheduled via config/recurring.yml.
class PurgeExpiredRecordingsJob < ApplicationJob
  queue_as :default

  def perform(retention_days: Scribe.config.raw_video_retention_days)
    cutoff = retention_days.to_i.days.ago
    scope = Recording.where(raw_video_purged_at: nil)
                     .where.not(storage_key: nil)
                     .where(created_at: ..cutoff)

    count = 0
    scope.find_each do |recording|
      RecordingPurge.purge_raw_video!(recording)
      count += 1
    rescue StandardError => e
      Rails.logger.warn(tag: "retention", recording_id: recording.id, message: e.message)
      Sentry.capture_exception(e, extra: { recording_id: recording.id }) if defined?(Sentry) && Sentry.initialized?
    end

    Rails.logger.info(tag: "retention", purged: count, cutoff: cutoff.iso8601)
    count
  end
end
