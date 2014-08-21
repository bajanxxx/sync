class DocumentRequest
  include Mongoid::Document

  field :consultant_name, type: String
  field :consultant_email, type: String
  field :document_type, type: String
  field :start_date, type: String
  field :end_date, type: String
  field :dated, type: String
  field :company, type: String
  field :status, type: String, default: 'pending' # approved | rejected | pending
  field :create_at, type: DateTime, default: DateTime.now
  field :approved_by, type: String # who approved the document request
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime
end
