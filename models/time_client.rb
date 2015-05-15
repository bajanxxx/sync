# Represents a Client in TimeSheets & Expenses module
class TimeClient
  include Mongoid::Document

  field :name, type: String
  field :address, type: String
  field :preferred_currency, type: String, default: 'USD'

  has_many :time_contacts, class_name: 'TimeContact'
  belongs_to :time_project, class_name: 'TimeProject'
end