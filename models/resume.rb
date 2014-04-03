class Resume
  include Mongoid::Document

  field :resume_id, type: String
  field :resume_name, type: String
  field :uploaded_date, type: DateTime
  field :_id, type: String, default: -> { resume_id }

  belongs_to :consultant, class_name: 'Consultant'
end
