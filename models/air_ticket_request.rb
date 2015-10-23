class AirTicketRequest
  include Mongoid::Document

  field :consultant_name, type: String # OLD
  field :consultant_first_name, type: String
  field :consultant_last_name, type: String
  field :consultant_email, type: String
  field :consultant_dob, type: String
  field :consultant_phone, type: String
  field :purpose, type: String
  field :travel_date, type: String
  field :from_apc, type: String
  field :flexible_from, type: Boolean, default: false
  field :from_apc2, type: String
  field :to_apc, type: String
  field :flexible_to, type: Boolean, default: false
  field :to_apc2, type: String
  field :flexibility, type: Boolean, default: false
  field :one_way, type: Boolean, default: false
  field :round_trip, type: Boolean, default: false
  field :return_date, type: String
  field :card_used, type: String
  field :amount, type: String # 100.00
  field :status, type: String, default: 'pending' # approved | rejected | pending
  field :created_at, type: DateTime, default: DateTime.now
  field :approved_by, type: String # who approved the document request
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime
  field :admin_created, type: Boolean, default: false
  field :notes, type: String, default: "N/A"
end
