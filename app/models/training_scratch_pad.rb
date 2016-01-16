class TrainingScratchPad
  include Mongoid::Document
  include Mongoid::Versioning

  # keep at most 5 versions of a document changes
  max_versions 5

  field :consultant_id, type: String
  field :contents, type: String, default: ''
  field :created_at, type: DateTime, default: DateTime.now
  field :last_saved_at, type: DateTime, default: DateTime.now

  belongs_to :training_sub_topic
end