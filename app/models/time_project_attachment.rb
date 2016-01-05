class TimeProjectAttachment
  include Mongoid::Document

  field :filename, type: String
  field :uploaded_date, type: String
  field :_id, type: String

  belongs_to :time_project, class_name: 'TimeProject'
end
