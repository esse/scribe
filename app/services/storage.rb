# Object-storage facade (SPEC §4, §5). All recordings, frames and exports live
# behind this so downloads are always served via short-lived signed URLs and the
# rest of the app never talks to S3 directly.
#
# Two adapters:
#   * Disk  — dev/test/CI. Files under config.storage_root; "signed URLs" are
#             app routes guarded by a short-lived HMAC token.
#   * S3    — production (Cloudflare R2 / MinIO / S3) via aws-sdk-s3 presigned URLs.
module Storage
  module_function

  def adapter
    @adapter ||= build_adapter
  end

  # Reset memoization (used by tests that flip ENV).
  def reset!
    @adapter = nil
  end

  def build_adapter
    case Scribe.config.storage_adapter
    when "s3" then S3Adapter.new
    else DiskAdapter.new
    end
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

    def signed_url(key, expires_in:, disposition:, filename:)
      expires_at = Time.current.to_i + expires_in.to_i
      token = Storage.sign_token(key, expires_at)
      params = { key:, expires_at:, token: }
      params[:disposition] = disposition if disposition
      params[:filename] = filename if filename
      "/storage/blob?#{params.to_query}"
    end
  end

  # --- S3 adapter ---------------------------------------------------------
  class S3Adapter
    def client
      @client ||= begin
        require "aws-sdk-s3"
        opts = {
          region: Scribe.config.s3_region,
          access_key_id: Scribe.config.s3_access_key_id,
          secret_access_key: Scribe.config.s3_secret_access_key
        }
        # R2 / MinIO need a custom endpoint + path-style addressing.
        if Scribe.config.s3_endpoint.present?
          opts[:endpoint] = Scribe.config.s3_endpoint
          opts[:force_path_style] = true
        end
        Aws::S3::Client.new(opts)
      end
    end

    def bucket = Scribe.config.storage_bucket

    def put(key, io_or_path, content_type:)
      body = io_or_path.respond_to?(:read) ? io_or_path : File.open(io_or_path, "rb")
      # Encrypt at rest (SPEC §14).
      client.put_object(bucket:, key:, body:, content_type:, server_side_encryption: "AES256")
      key
    ensure
      body.close if body && !io_or_path.respond_to?(:read)
    end

    def get(key)
      client.get_object(bucket:, key:).body.read
    end

    def download_to(key, path)
      FileUtils.mkdir_p(File.dirname(path))
      client.get_object(response_target: path.to_s, bucket:, key:)
      path
    end

    def delete(key)
      client.delete_object(bucket:, key:)
    end

    def exists?(key)
      client.head_object(bucket:, key:)
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    def signed_url(key, expires_in:, disposition:, filename:)
      params = { bucket:, key:, expires_in: expires_in.to_i }
      if disposition || filename
        cd = +"#{disposition || 'attachment'}"
        cd << "; filename=\"#{filename}\"" if filename
        params[:response_content_disposition] = cd
      end
      Aws::S3::Presigner.new(client:).presigned_url(:get_object, **params)
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
