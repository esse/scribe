class ExportsController < ApplicationController
  before_action :set_export

  # GET /exports/:id — status + signed download URL (SPEC §13).
  def show
    render json: {
      id: @export.id,
      format: @export.format,
      status: @export.status,
      file_size: @export.file_size,
      error_message: @export.error_message,
      download_url: @export.ready? ? Storage.signed_url(@export.storage_key, disposition: "attachment") : nil
    }
  end

  private

  def set_export
    @export = Export.joins(manual: { recording: :user })
                    .where(users: { id: Current.user.id })
                    .find(params[:id])
  end
end
