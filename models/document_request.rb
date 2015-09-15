class DocumentRequest
  include Mongoid::Document

  field :consultant_name, type: String
  field :consultant_email, type: String
  field :document_type, type: String
  field :start_date, type: String
  field :end_date, type: String
  field :position, type: String
  field :dated, type: String
  field :company, type: String
  field :status, type: String, default: 'pending' # approved | rejected | pending
  field :created_at, type: DateTime, default: DateTime.now
  field :approved_by, type: String # who approved the document request
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime
  field :filename, type: String
  field :file_id, type: String
  field :uploaded_at, type: DateTime
  field :admin_created, type: Boolean, default: false
  field :notes, type: String, default: "N/A"
end
