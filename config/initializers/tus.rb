# Resumable upload server (SPEC §7.2). MediaRecorder emits a streaming WebM whose
# later chunks aren't standalone files, so tus performs an ordered, resumable
# byte-append and the final object is one valid WebM.
#
# Dev/test back tus with the local filesystem; production should point its store
# at S3/R2 (configure here from ENV when deploying).
require "tus/server"

tus_dir = ENV.fetch("TUS_DATA_DIR", Rails.root.join("tmp/tus-data").to_s)
FileUtils.mkdir_p(tus_dir)

Tus::Server.opts[:storage] = Tus::Storage::Filesystem.new(tus_dir)
Tus::Server.opts[:max_size] = ENV.fetch("TUS_MAX_SIZE", 5 * 1024 * 1024 * 1024).to_i # 5 GB
Tus::Server.opts[:redirect_download] = nil

module Scribe
  def self.tus_data_dir
    ENV.fetch("TUS_DATA_DIR", Rails.root.join("tmp/tus-data").to_s)
  end
end
