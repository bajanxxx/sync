class TrainingProjectSubmission
  include Mongoid::Document
  include Mongoid::Versioning

  # keep at most 5 versions of a document changes
  max_versions 5

  field :submission_link, type: String, default: ''
  field :consultant_id, type: String
  # APPROVED, REDO, SUBMITTED
  field :status, type: String, default: 'SUBMITTED'

  belongs_to :training_project
end
