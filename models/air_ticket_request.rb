class AirTicketRequest
  include Mongoid::Document

  field :consultant_name, type: String
  field :consultant_email, type: String
  field :purpose, type: String
  field :travel_date, type: String
  field :from_apc, type: String
  field :to_apc, type: String
  field :flexibility, type: Integer
  field :card_used, type: String
  field :amount, type: String # 100.00
  field :status, type: String, default: 'pending' # approved | rejected | pending
  field :created_at, type: DateTime, default: DateTime.now
  field :approved_by, type: String # who approved the document request
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime
  field :admin_created, type: Boolean, default: false
end
