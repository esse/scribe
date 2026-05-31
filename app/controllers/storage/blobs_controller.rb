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
      send_data ::Storage.get(key),
                disposition:,
                filename: params[:filename].presence || File.basename(key),
                type: content_type_for(key)
    end

    private

    def content_type_for(key)
      Marcel::MimeType.for(name: key)
    end
  end
end
