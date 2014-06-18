class Customer
  include Mongoid::Document

  field :company_id, type: String
  field :company, type: String
  field :first_name, type: String
  field :last_name, type: String
  field :has_gatekeeper, type: String, default: "No"
  field :is_business_unit_id_head, type: String
  field :title, type: String
  field :address_line1, type: String
  field :address_line2, type: String
  field :city, type: String
  field :state, type: String
  field :zip, type: Integer
  field :phone, type: String
  field :extension, type: String
  field :fax, type: String
  field :email, type: String
  field :industry, type: String
  field :it_budget_million, type: Float
  field :it_employees, type: Integer
  field :revenue_billion, type: Float
  field :fiscal_year_end, type: String
  field :duns, type: String

  field :emails_sent, type: Integer, default: 0
  field :email_remainders_sent, type: Integer, default: 0
  field :email_replies_recieved, type: Integer, default: 0
  field :unsubscribed, type: Boolean, default: false
  field :bounced, type: Boolean, default: false
  field :skipped, type: Boolean, default: false
  field :skipper_subjects, type: Array, default: []

  index({industry: 1, email: 1})
end
