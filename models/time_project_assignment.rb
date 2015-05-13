# Represents a project_assignment in TimeSheets & Expenses module
class TimeProjectAssignment
  include Mongoid::Document

  field :consultant, type: String # email_id of the consultant
  field :start_date, type: Date
  field :end_date, type: Date
  field :notes, type: String

  belongs_to :time_project, class_name: 'TimeProject'
end