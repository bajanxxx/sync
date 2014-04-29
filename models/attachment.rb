class Attachement
  include Mongoid::Document

  field :filename, type: String
  field :timestamp, type: String
  field :_id, type: String

  belongs_to :email, class_name: 'Email'
end
