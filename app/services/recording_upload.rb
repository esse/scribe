# Moves a finished tus upload into our object storage and probes it (SPEC §7.2
# step 4). The tus filesystem store keeps each completed upload at <dir>/<uid>.
module RecordingUpload
  module_function

  StorageKeyFor = ->(recording) { "recordings/#{recording.id}/source.webm" }

  # Copies the assembled upload to storage, returns { storage_key:, duration_seconds:, mime: }.
  def finalize(recording, tus_upload_id)
    source_path = tus_file_path(tus_upload_id)
    raise "tus upload #{tus_upload_id} not found" unless source_path && File.exist?(source_path)

    storage_key = StorageKeyFor.call(recording)
    Storage.put(storage_key, source_path, content_type: "video/webm")

    meta = Media::Probe.metadata(source_path)
    { storage_key:, duration_seconds: meta[:duration_seconds], mime: meta[:mime] }
  end

  # tus stores the completed file at <data_dir>/<uid> (uid is the last path
  # segment of the tus upload URL).
  def tus_file_path(tus_upload_id)
    uid = tus_upload_id.to_s.split("/").last
    return nil if uid.blank?

    File.join(Scribe.tus_data_dir, uid)
  end
end
