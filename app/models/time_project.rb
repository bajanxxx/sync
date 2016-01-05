# Represents a project in TimeSheets & Expenses module
class TimeProject
  include Mongoid::Document

  TYPES = [ :direct_client, :staff_augmentation ]
  INVOICE_TYPES = [ :task_hourly_rate, :person_hourly_rate, :project_hourly_rate, :project_flat_rate, :monthly_flat_rate ]
  BUDGET_TYPES = [ :total_project_hours, :total_project_fees, :hours_per_task, :hours_per_person ]

  field :name, type: String
  field :project_code, type: String
  field :type, type: String
  field :start_date, type: Date
  field :end_date, type: Date
  field :notes, type: String
  field :billable?, type: Boolean, default: false
  field :invoice_method, type: String # TASK_HOURLY, PERSON_HOURLY, PROJECT_HOURLY, NONE
  field :project_hourly_price, type: String, default: '0.00'
  field :budget?, type: Boolean, default: false
  field :budget_method, type: String # TOTAL_PROJECT_HOURS, TOTAL_PROJECT_FEES, HOURS_PER_TASK, HOURS_PER_PERSON
  field :budget_project_minutes, type: Integer
  field :budget_project_fees, type: String, default: '0.00'
  field :project_flat_rate, type: String, default: '0.00'
  field :project_monthly_flat_rate, type: String, default: '0.00'
  field :team, type: Array, default: []
  field :sales, type: String
  field :vendor_id, type: String
  field :client_id, type: String
  field :_id, type: String, default: -> { project_code }

  has_many :time_project_tasks, class_name: 'TimeProjectTask'
  has_many :time_project_team_members, class_name: 'TimeProjectTeamMember'
  has_many :time_project_attachments, class_name: 'TimeProjectAttachment'
  # has_many :time_project_assignments, class_name: 'TimeProjectAssignment'
  has_many :timesheets, class_name: 'Timesheet'
end