# Resumable upload server (SPEC §7.2). MediaRecorder emits a streaming WebM whose
# later chunks aren't standalone files, so tus performs an ordered, resumable
# byte-append and the final object is one valid WebM.
#
# Local-first: tus uploads are buffered on the filesystem, under the data dir so
# in-flight uploads live in the same mountable folder as everything else.
require "tus/server"

tus_dir = ENV.fetch("TUS_DATA_DIR", File.join(Scribe.config.data_dir, "tus"))
FileUtils.mkdir_p(tus_dir)

Tus::Server.opts[:storage] = Tus::Storage::Filesystem.new(tus_dir)
Tus::Server.opts[:max_size] = ENV.fetch("TUS_MAX_SIZE", 5 * 1024 * 1024 * 1024).to_i # 5 GB
Tus::Server.opts[:redirect_download] = nil

module Scribe
  def self.tus_data_dir
    ENV.fetch("TUS_DATA_DIR", File.join(Scribe.config.data_dir, "tus"))
  end
end
