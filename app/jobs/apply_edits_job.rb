# Optional pipeline stage 0: apply the in-browser editor's trim before
# transcription. Reads the recording's keep-segments, cuts the source video with
# ffmpeg (stream-copy, so even multi-hour recordings finish in seconds), stores
# the trimmed result alongside the original, and updates the duration so the rest
# of the pipeline — and credit metering — works on the edited video.
#
# A full-length / empty edit list is a no-op pass-through straight to transcription.
class ApplyEditsJob < ApplicationJob
  include PipelineStage
  queue_as :default

  def perform(recording_id)
    recording = Recording.find(recording_id)
    return if recording.complete?

    run_stage(recording, stage: :editing) do
      recording.editing! unless recording.editing?

      segments = Media::Editor.normalize_segments(
        recording.edit_segments, duration_seconds: recording.duration_seconds
      )

      apply_trim(recording, segments) unless Media::Editor.full_length?(segments, duration_seconds: recording.duration_seconds)

      recording.uploaded! # hand back to the linear pipeline's entry state
      TranscribeJob.perform_later(recording.id)
    end
  end

  private

  def apply_trim(recording, segments)
    # Always cut from the pristine source so re-editing/retry is idempotent.
    with_source_video(recording, key: recording.storage_key) do |src, dir|
      out = File.join(dir, "edited#{File.extname(src)}")
      Media::Editor.cut(input_path: src, output_path: out, segments:)

      edited_key = "recordings/#{recording.id}/edited#{File.extname(src)}"
      Storage.put(edited_key, out, content_type: recording.mime.presence || "video/webm")

      meta = Media::Probe.metadata(out)
      recording.update!(
        edited_storage_key: edited_key,
        duration_seconds: meta[:duration_seconds].positive? ? meta[:duration_seconds] : Media::Editor.kept_duration(segments)
      )
    end
  end
end
