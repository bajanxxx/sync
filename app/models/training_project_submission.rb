class TrainingProjectSubmission
  include Mongoid::Document
  include Mongoid::Versioning

  # keep at most 5 versions of a document changes
  max_versions 5

  field :submission_link, type: String, default: ''
  field :consultant_id, type: String
  field :created_at, type: DateTime, default: DateTime.now
  # APPROVED, REDO, SUBMITTED
  field :status, type: String, default: 'SUBMITTED'
  field :resubmission, type: Boolean, default: false
  field :redo_reason, type: String

  belongs_to :training_project
end
