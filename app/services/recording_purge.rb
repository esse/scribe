# Storage cleanup for recordings (SPEC §14). Two operations:
#   * purge_raw_video! — retention: delete the source video but keep the manual,
#     frames and exports (so generated docs still render).
#   * destroy! — full delete: remove every stored object then the DB rows.
module RecordingPurge
  module_function

  # Delete the raw source video (and the trimmed copy, if any) and mark it
  # purged. Idempotent.
  def purge_raw_video!(recording)
    if recording.raw_video_purged_at.nil?
      Storage.delete(recording.storage_key) if recording.storage_key.present?
      Storage.delete(recording.edited_storage_key) if recording.edited_storage_key.present?
    end
    recording.update!(raw_video_purged_at: Time.current)
  end

  # Remove all stored objects for a recording, then destroy it (DB rows cascade
  # via dependent: :destroy). Storage is best-effort so a missing object never
  # blocks the delete.
  def destroy!(recording)
    storage_keys(recording).each { |key| safe_delete(key) }
    recording.destroy!
  end

  # Every storage key owned by a recording: source video, frames (+ thumbnails),
  # and export artifacts.
  def storage_keys(recording)
    keys = []
    keys << recording.storage_key if recording.storage_key.present?
    keys << recording.edited_storage_key if recording.edited_storage_key.present?
    recording.frames.each do |frame|
      keys << frame.storage_key
      keys << frame.thumbnail_storage_key
    end
    recording.manual&.exports&.each { |export| keys << export.storage_key }
    keys.compact.uniq
  end

  def safe_delete(key)
    Storage.delete(key)
  rescue StandardError => e
    Rails.logger.warn(tag: "recording_purge", message: "failed to delete #{key}: #{e.message}")
  end
end
