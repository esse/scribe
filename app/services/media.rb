# ffmpeg/ffprobe binary locations (SPEC §4 — system ffmpeg invoked from jobs).
module Media
  module_function

  def ffmpeg_bin = ENV.fetch("FFMPEG_BIN", "ffmpeg")
  def ffprobe_bin = ENV.fetch("FFPROBE_BIN", "ffprobe")
end
