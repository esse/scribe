# Pipeline stage 2: scene-detected frame extraction (SPEC §8.4).
class ExtractFramesJob < ApplicationJob
  include PipelineStage
  queue_as :default

  def perform(recording_id)
    recording = Recording.find(recording_id)
    return if recording.complete?

    run_stage(recording, stage: :frame_extraction) do
      recording.extracting_frames!

      with_source_video(recording) do |video_path, dir|
        out_dir = File.join(dir, "frames")
        candidates = Media::FrameExtractor.extract(
          input_path: video_path,
          out_dir:,
          threshold: recording.scene_threshold,
          duration_seconds: recording.duration_seconds.to_f
        )
        candidates.each { |c| persist_frame(recording, c, dir) }
      end

      GenerateManualJob.perform_later(recording.id)
    end
  end

  private

  # Upsert keyed on (recording_id, timestamp_ms) so re-runs don't duplicate (SPEC §5).
  def persist_frame(recording, candidate, work_dir)
    frame = recording.frames.find_or_initialize_by(timestamp_ms: candidate[:timestamp_ms])
    return frame if frame.persisted? && Storage.exists?(frame.storage_key.to_s)

    base = "recordings/#{recording.id}/frames/#{candidate[:timestamp_ms]}"
    full_key = "#{base}.png"
    thumb_path = File.join(work_dir, "thumb_#{candidate[:timestamp_ms]}.png")
    Media::FrameExtractor.thumbnail(src_path: candidate[:path], out_path: thumb_path)
    thumb_key = "#{base}_thumb.png"

    Storage.put(full_key, candidate[:path], content_type: "image/png")
    Storage.put(thumb_key, thumb_path, content_type: "image/png")
    width, height = Media::FrameExtractor.dimensions(candidate[:path])

    frame.assign_attributes(
      storage_key: full_key,
      thumbnail_storage_key: thumb_key,
      width:, height:, source: :scene
    )
    frame.save!
    frame
  end
end
