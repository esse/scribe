# Pipeline stage 1: extract audio and transcribe (SPEC §8.2, §8.3, §9.3).
class TranscribeJob < ApplicationJob
  include PipelineStage
  queue_as :default

  def perform(recording_id)
    recording = Recording.find(recording_id)
    return if recording.complete? # already done; idempotent no-op

    run_stage(recording, stage: :transcription) do
      recording.transcribing!

      result = with_source_video(recording) do |video_path, dir|
        audio_path = File.join(dir, "audio.flac")
        Media::AudioExtractor.extract(input_path: video_path, output_path: audio_path)
        Transcription::Base.build.transcribe(audio_path:)
      end

      persist_transcript(recording, result)
      ExtractFramesJob.perform_later(recording.id)
    end
  end

  private

  # Upsert keyed by recording so a re-run replaces rather than duplicates (SPEC §5).
  def persist_transcript(recording, result)
    Transcript.transaction do
      transcript = Transcript.find_or_initialize_by(recording:)
      transcript.assign_attributes(
        provider: Scribe.config.transcription_provider,
        language: result[:language],
        full_text: result[:full_text],
        raw_payload: result[:raw] || {},
        status: :ready
      )
      transcript.save!
      transcript.segments.delete_all
      result[:segments].each_with_index do |seg, i|
        transcript.segments.create!(position: i, start_ms: seg[:start_ms], end_ms: seg[:end_ms], text: seg[:text].to_s)
      end
    end
  end
end
