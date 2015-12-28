class Consultant
  include Mongoid::Document

  field :email, type: String
  field :domain, type: String # us, eu, in
  field :team, type: Integer
  field :phone, type: String
  field :location, type: String # current location of the consultant
  field :_id, type: String, default: -> { email }

  has_many :applications, class_name: 'Application'
  has_many :resumes, class_name: 'Resume'
  has_one :details, class_name: 'Detail'
end
