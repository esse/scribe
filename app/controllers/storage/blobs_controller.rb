module Storage
  # Serves disk-adapter signed URLs (SPEC §5). The HMAC token *is* the
  # authorization, so this endpoint is unauthenticated but token-gated. In
  # production the S3 adapter issues presigned URLs and this is unused.
  class BlobsController < ApplicationController
    allow_unauthenticated_access

    def show
      key = params[:key].to_s
      unless ::Storage.valid_token?(key, params[:expires_at], params[:token])
        head(:forbidden) and return
      end
      head(:not_found) and return unless ::Storage.exists?(key)

      disposition = params[:disposition].presence || "inline"
      filename = params[:filename].presence || File.basename(key)
      type = content_type_for(key)

      # Stream from disk when possible so the in-browser editor can seek a
      # multi-hour video over HTTP Range requests without us buffering the whole
      # file into memory. Falls back to an in-memory send for non-disk stores.
      if (path = ::Storage.local_path(key))
        send_file path, disposition:, filename:, type:
      else
        send_data ::Storage.get(key), disposition:, filename:, type:
      end
    end

    private

    def content_type_for(key)
      Marcel::MimeType.for(name: key)
    end
  end
end
