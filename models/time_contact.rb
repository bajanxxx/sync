class TimeContact
  include Mongoid::Document

  field :first_name, type: String
  field :last_name, type: String
  field :title, type: String
  field :email, type: String
  field :office_num, type: String
  field :mobile_num, type: String
  field :fax_num, type: String

  belongs_to :time_vendor, class_name: 'TimeVendor'
  belongs_to :time_client, class_name: 'TimeClient'
end