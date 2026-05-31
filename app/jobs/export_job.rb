# Renders a manual to a requested format and stores the artifact (SPEC §11.3).
class ExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    export = Export.find(export_id)
    return if export.ready?

    manual = export.manual
    exporter = Exporters::Registry.for(export.format).new
    result = exporter.export(manual)

    data = result.io.read
    key = "exports/#{manual.id}/#{export.id}/#{result.filename}"
    Storage.put(key, StringIO.new(data), content_type: result.content_type)

    export.update!(status: :ready, storage_key: key, file_size: data.bytesize, error_message: nil)
  rescue StandardError => e
    export&.update(status: :failed, error_message: e.message.to_s.truncate(1000))
    Rails.logger.error(tag: "export_error", export_id:, message: e.message)
  end
end
