# Represents summary of information on the timesheet, which week its for, comments, etc
class Timesheet
  include Mongoid::Document

  field :project_code, type: String
  field :consultant, type: String # email id of the time sheet
  field :week, type: Date # represents weak
  field :total_hours, type: Float, default: 0.00
  field :status, type: String, default: 'NOT SUBMITTED' # SAVED, SUBMITTED, APPROVED, REJECTED
  field :notes, type: String
  field :created_at, type: DateTime, default: DateTime.now
  field :submitted_at, type: DateTime
  field :saved_at, type: DateTime
  field :approved_by, type: String
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime

  has_many :timesheet_details, class_name: 'TimesheetDetail'
  has_many :timesheet_attachments, class_name: 'TimesheetAttachment'
  belongs_to :time_project, class_name: 'TimeProject'
end