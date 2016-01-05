# Represents a row for each day and each project with the hours worked, this grows fast
class TimesheetDetail
  include Mongoid::Document

  field :workday, type: Date
  field :hours, type: Float, default: 0.00
  field :logged_at, type: DateTime

  belongs_to :timesheet, class_name: 'Timesheet'
end