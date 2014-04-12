class Application
  include Mongoid::Document

  # field :job_id, type: Array
  field :job_url, type: String
  field :comments, type: Array
  field :notes, type: String
  field :resume_id, type: String
  field :status, type: Array # [ 'APPLIED', 'CHECKING', 'AWAITING_UPDATE_FROM_USER', 'AWAITING_UPDATE_FROM_VENDOR', 'FOLLOW_UP' ]
  field :closing_status, type: Array # %w(BILLING_RATE_NOT_NEGOTIATED UNDER_QUALIFIED INTERVIEW_FAILED APPROVED)
  field :hide, type: Boolean, default: false

  belongs_to :consultant, class_name: 'Consultant'
  belongs_to :job, class_name: 'Job'
end
