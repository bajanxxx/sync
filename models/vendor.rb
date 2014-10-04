class Vendor
  include Mongoid::Document

  field :email, type: String
  field :company, type: String
  field :first_name, type: String, default: ''
  field :last_name, type: String
  field :phone, type: String
  field :emails_sent, type: Integer, default: 0
  field :email_remainders_sent, type: Integer, default: 0
  field :email_replies_recieved, type: Integer, default: 0
  field :unsubscribed, type: Boolean, default: false
  field :bounced, type: Boolean, default: false
  field :skipped, type: Boolean, default: false
  field :skipped_templates, type: Array, default: []
  field :sent_templates, type: Array, default: []

  index({email: 1})
end
