class TrainingResource
  include Mongoid::Document

  field :filename, type: String
  field :uploaded_date, type: DateTime, default: DateTime.now
  field :filetype, type: String
  field :_id, type: String

  belongs_to :training_topic
end