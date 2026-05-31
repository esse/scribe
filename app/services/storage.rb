# Object-storage facade. Local-first: everything lives on disk under the data
# dir (config.storage_root), so the whole store is just files in a folder you
# can mount into a container. Downloads are still served via short-lived signed
# (HMAC) app URLs so blobs aren't world-readable through the web server.
module Storage
  module_function

  def adapter
    @adapter ||= DiskAdapter.new
  end

  # Reset memoization (used by tests that flip ENV).
  def reset!
    @adapter = nil
  end

  def put(key, io_or_path, content_type: "application/octet-stream")
    adapter.put(key, io_or_path, content_type:)
  end

  def get(key)
    adapter.get(key)
  end

  def download_to(key, path)
    adapter.download_to(key, path)
  end

  def delete(key)
    adapter.delete(key)
  end

  def exists?(key)
    adapter.exists?(key)
  end

  # Local filesystem path for a key. Lets the blob endpoint stream large files
  # (with HTTP Range support) instead of buffering them in memory.
  def local_path(key)
    adapter.local_path(key)
  end

  # Short-lived signed download URL (SPEC §5, §14).
  def signed_url(key, expires_in: Scribe.config.signed_url_ttl, disposition: nil, filename: nil)
    adapter.signed_url(key, expires_in:, disposition:, filename:)
  end

  # --- Disk adapter -------------------------------------------------------
  class DiskAdapter
    def root = Pathname.new(Scribe.config.storage_root)

    def path_for(key) = root.join(key)

    def put(key, io_or_path, content_type: nil)
      dest = path_for(key)
      FileUtils.mkdir_p(dest.dirname)
      if io_or_path.respond_to?(:read)
        File.open(dest, "wb") { |f| IO.copy_stream(io_or_path, f) }
      else
        FileUtils.cp(io_or_path.to_s, dest)
      end
      key
    end

    def get(key) = File.binread(path_for(key))

    def download_to(key, path)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(path_for(key).to_s, path.to_s)
      path
    end

    def delete(key)
      FileUtils.rm_f(path_for(key))
    end

    def exists?(key) = File.exist?(path_for(key))

    def local_path(key)
      path = path_for(key)
      File.exist?(path) ? path.to_s : nil
    end

    def signed_url(key, expires_in:, disposition:, filename:)
      expires_at = Time.current.to_i + expires_in.to_i
      token = Storage.sign_token(key, expires_at)
      params = { key:, expires_at:, token: }
      params[:disposition] = disposition if disposition
      params[:filename] = filename if filename
      "/storage/blob?#{params.to_query}"
    end
  end

  # HMAC for the disk adapter's signed URLs. Keyed on the app secret so tokens
  # can't be forged client-side.
  def sign_token(key, expires_at)
    OpenSSL::HMAC.hexdigest("SHA256", signing_secret, "#{key}|#{expires_at}")
  end

  def valid_token?(key, expires_at, token)
    return false if expires_at.to_i < Time.current.to_i

    ActiveSupport::SecurityUtils.secure_compare(token.to_s, sign_token(key, expires_at.to_i))
  end

  def signing_secret
    Rails.application.secret_key_base
  end
end
