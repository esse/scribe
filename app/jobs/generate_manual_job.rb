# Pipeline stage 3: alignment + manual generation (SPEC §8.5, §9) — the core.
# Asks Claude for an ordered manual, snaps each chosen frame to a real row
# (extracting on demand if needed), persists, completes, and settles the hold.
class GenerateManualJob < ApplicationJob
  include PipelineStage
  queue_as :default

  # Snap tolerance: how close an existing frame must be before we extract a new
  # one on demand (SPEC §8.5).
  SNAP_TOLERANCE_MS = 750

  def perform(recording_id)
    recording = Recording.find(recording_id)
    return if recording.complete?

    run_stage(recording, stage: :manual_generation) do
      recording.generating_manual!
      manual = Manual.find_or_initialize_by(recording:)
      manual.update!(status: :generating)

      result = ManualGeneration::Generator.new(recording:).call

      with_source_video(recording) do |video_path, dir|
        persist_manual(recording, manual, result, video_path, dir)
      end

      recording.complete!
      Credits::Ledger.settle!(recording.credit_hold)
    end
  end

  private

  def persist_manual(recording, manual, result, video_path, work_dir)
    Manual.transaction do
      manual.update!(
        title: result.title,
        summary: result.summary,
        model: result.model,
        status: :ready,
        generated_at: Time.current
      )
      manual.steps.delete_all

      result.steps.each_with_index do |step, i|
        frame = resolve_frame(recording, step["frame_timestamp_ms"].to_i, video_path, work_dir)
        manual.steps.create!(
          position: i,
          title: step["title"],
          body_markdown: step["body_markdown"],
          source_start_ms: step["source_start_ms"],
          source_end_ms: step["source_end_ms"],
          frame:
        )
      end
    end
  end

  # Snap Claude's chosen timestamp to a real frame; extract on demand if the
  # nearest existing frame is too far away (SPEC §8.5).
  def resolve_frame(recording, timestamp_ms, video_path, work_dir)
    exact = recording.frames.find_by(timestamp_ms:)
    return exact if exact

    nearest = Frame.nearest_to(recording, timestamp_ms)
    return nearest if nearest && (nearest.timestamp_ms - timestamp_ms).abs <= SNAP_TOLERANCE_MS

    extract_on_demand(recording, timestamp_ms, video_path, work_dir)
  end

  def extract_on_demand(recording, timestamp_ms, video_path, work_dir)
    candidate = Media::FrameExtractor.frame_at(input_path: video_path, timestamp_ms:, out_dir: work_dir)
    base = "recordings/#{recording.id}/frames/#{timestamp_ms}"
    thumb_path = File.join(work_dir, "od_thumb_#{timestamp_ms}.png")
    Media::FrameExtractor.thumbnail(src_path: candidate[:path], out_path: thumb_path)

    Storage.put("#{base}.png", candidate[:path], content_type: "image/png")
    Storage.put("#{base}_thumb.png", thumb_path, content_type: "image/png")
    width, height = Media::FrameExtractor.dimensions(candidate[:path])

    recording.frames.create!(
      timestamp_ms:,
      storage_key: "#{base}.png",
      thumbnail_storage_key: "#{base}_thumb.png",
      width:, height:, source: :on_demand
    )
  end
end
