require "test_helper"

# The in-browser editor's edit-decision-list math (segment validation/merging)
# and the ffmpeg cut. The pure-Ruby normalization is the part that must be
# bullet-proof regardless of input; the cut itself needs ffmpeg and is skipped
# where the binary isn't available.
class MediaEditorTest < ActiveSupport::TestCase
  test "normalize clamps, drops tiny ranges, and sorts" do
    segs = Media::Editor.normalize_segments(
      [ { "start" => -5, "end" => 10 }, { "start" => 90, "end" => 200 }, { "start" => 30, "end" => 30.05 } ],
      duration_seconds: 100
    )
    assert_equal [ [ 0.0, 10.0 ], [ 90.0, 100.0 ] ], segs
  end

  test "normalize merges overlapping and touching ranges" do
    segs = Media::Editor.normalize_segments(
      [ [ 0, 30 ], [ 25, 40 ], [ 40.02, 60 ] ],
      duration_seconds: 120
    )
    assert_equal [ [ 0.0, 60.0 ] ], segs
  end

  test "normalize accepts symbol and array shapes and ignores junk" do
    segs = Media::Editor.normalize_segments(
      [ { start: 1, end: 5 }, [ 10, 12 ], "nonsense", { start: 1 } ],
      duration_seconds: 60
    )
    assert_equal [ [ 1.0, 5.0 ], [ 10.0, 12.0 ] ], segs
  end

  test "full_length? recognises an untrimmed recording" do
    assert Media::Editor.full_length?([], duration_seconds: 100)
    assert Media::Editor.full_length?([ [ 0, 100 ] ], duration_seconds: 100)
    assert_not Media::Editor.full_length?([ [ 0, 50 ] ], duration_seconds: 100)
    assert_not Media::Editor.full_length?([ [ 0, 40 ], [ 60, 100 ] ], duration_seconds: 100)
  end

  test "kept_duration sums the segments" do
    assert_in_delta 70.0, Media::Editor.kept_duration([ [ 0, 40 ], [ 60, 90 ] ]), 0.001
  end

  test "cut trims a real video down to the kept segments" do
    skip "ffmpeg not available" unless ffmpeg_available?

    Dir.mktmpdir do |dir|
      src = File.join(dir, "src.mp4")
      build_test_video(src, seconds: 6)
      out = File.join(dir, "out.mp4")

      Media::Editor.cut(input_path: src, output_path: out, segments: [ [ 0.0, 2.0 ] ])

      assert File.exist?(out)
      assert_operator Media::Probe.duration_seconds(out), :<, 5.0, "output should be shorter than the source"
    end
  end

  private

  def ffmpeg_available?
    system("#{Media.ffmpeg_bin} -version", out: File::NULL, err: File::NULL)
  end

  def build_test_video(path, seconds:)
    _o, err, st = Open3.capture3(
      Media.ffmpeg_bin, "-y",
      "-f", "lavfi", "-i", "testsrc=duration=#{seconds}:size=160x120:rate=10",
      "-pix_fmt", "yuv420p", path
    )
    raise "ffmpeg failed: #{err}" unless st.success?
  end
end
