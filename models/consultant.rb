class Consultant
  include Mongoid::Document

  field :first_name, type: String
  field :last_name, type: String
  field :team, type: Integer
  field :email, type: String
  field :_id, type: String, default: -> { email }

  has_many :applications, class_name: 'Application'
  has_many :resumes, class_name: 'Resume'
end
