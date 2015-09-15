class CertificationRequest
  include Mongoid::Document

  field :consultant_name, type: String
  field :consultant_first_name, type: String
  field :consultant_last_name, type: String
  field :consultant_email, type: String
  field :purpose, type: String
  field :booking_date, type: String
  field :flexibility, type: Boolean, default: false
  field :time_preference, type: String, default: 'MNG' # MNG | NOON
  field :card_used, type: String
  field :name, type: String
  field :short, type: String
  field :code, type: String
  field :amount, type: String # 100.00
  field :status, type: String, default: 'pending' # approved | rejected | pending | completed - either pass or fail
  field :created_at, type: DateTime, default: DateTime.now
  field :approved_by, type: String # who approved the document request
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime
  field :pass, type: Boolean
  field :admin_created, type: Boolean, default: false
  field :notes, type: String, default: "N/A"
end
