class Resume
  include Mongoid::Document

  field :resume_name, type: String
  field :uploaded_date, type: DateTime
  field :_id, type: String

  belongs_to :consultant, class_name: 'Consultant'
end
