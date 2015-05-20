class TimesheetAttachment
  include Mongoid::Document

  field :filename, type: String
  field :uploaded_date, type: String
  field :_id, type: String

  belongs_to :timesheet, class_name: 'Timesheet'
end
