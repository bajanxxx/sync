# Track email opens and clicks
class Tracking
  include Mongoid::Document

  field :recipient, type: String # email
  field :domain, type: String
  field :device_type, type: String
  field :country, type: String
  field :region, type: String
  field :client_name, type: String
  field :user_agent, type: String
  field :client_os, type: String
  field :ip, type: String
  field :client_type, type: String
  field :event, type: String # opened | clicked
  field :timestamp, type: String
  field :campaign_id, type: String

  index({recipient: 1})
end
