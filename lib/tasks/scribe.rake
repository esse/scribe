# Local-first CLI: turn an existing screen recording into a manual without the
# browser. Point it at a video file and it runs the whole pipeline.
#
#   bin/rails "scribe:ingest[/path/to/screen-recording.mp4]"
#
# By default it runs inline (no worker needed) and prints where the result files
# were written. Pass a second arg to enqueue instead of running inline:
#
#   bin/rails "scribe:ingest[/path/to/clip.mp4,async]"
namespace :scribe do
  desc "Process an existing video file into a manual (CLI). Usage: scribe:ingest[path]"
  task :ingest, %i[path mode] => :environment do |_t, args|
    path = args[:path]
    abort "Usage: bin/rails \"scribe:ingest[/path/to/video.mp4]\"" if path.blank?

    inline = args[:mode].to_s != "async"
    puts "Ingesting #{path} (#{inline ? 'inline' : 'async'})…"

    recording = RecordingIngest.from_path(path, inline:)
    recording.reload

    if inline
      if recording.complete?
        dir = ResultFiles.results_path(recording) || "(result files disabled)"
        puts "✓ Manual ready for recording ##{recording.id}: #{recording.manual&.title}"
        puts "  Result files: #{dir}"
      else
        warn "✗ Pipeline ended in status=#{recording.status} (failed_stage=#{recording.failed_stage}): #{recording.error_message}"
        exit 1
      end
    else
      puts "Enqueued recording ##{recording.id}. Run `bin/jobs` to process it."
    end
  end

  desc "List recordings and their status"
  task list: :environment do
    Recording.order(:created_at).each do |r|
      puts format("#%-4d %-18s %-22s %s", r.id, r.status, r.manual&.title.to_s.truncate(20), r.created_at)
    end
  end
end
