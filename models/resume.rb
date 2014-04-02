class Resume
  include Mongoid::Document

  field :resume_id, type: String
  field :_id, type: String, default: -> { resume_id }

  belongs_to :consultant, class_name: 'Consultant'
end
