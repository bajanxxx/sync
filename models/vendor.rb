class Vendor
  include Mongoid::Document

  field :email, type: String
  field :company, type: String
  field :first_name, type: String
  field :last_name, type: String
  field :phone, type: String
  field :emails_sent, type: Integer, default: 0
  field :email_remainders_sent, type: Integer, default: 0
  field :email_replies_recieved, type: Integer, default: 0
  field :unsubscribed, type: Boolean, default: false
  field :_id, type: String, default: -> { email }
end
