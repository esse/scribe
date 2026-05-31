module Manuals
  # Export creation + format discovery (SPEC §11.3, §13).
  class ExportsController < ApplicationController
    before_action :set_manual

    # GET /manuals/:manual_id/exports/formats — data-driven UI (SPEC §11.1).
    def formats
      render json: { formats: Exporters::Registry.formats }
    end

    # POST /manuals/:manual_id/exports { format }
    def create
      format = params.require(:format)
      unless Exporters::Registry.formats.include?(format)
        render json: { error: "unknown_format", formats: Exporters::Registry.formats }, status: :unprocessable_entity
        return
      end

      export = @manual.exports.create!(format:, status: :pending)
      ExportJob.perform_later(export.id)
      render json: { export_id: export.id, status: export.status }, status: :accepted
    end

    private

    def set_manual
      @manual = Manual.joins(recording: :user)
                      .where(users: { id: Current.user.id })
                      .find(params[:manual_id])
    end
  end
end
