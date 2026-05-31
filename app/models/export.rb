class Export < ApplicationRecord
  belongs_to :manual

  enum :status, { pending: 0, ready: 1, failed: 2 }

  validates :format, presence: true,
                     inclusion: { in: ->(_) { Exporters::Registry.formats } }
end
