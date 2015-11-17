# Represents a project in TimeSheets & Expenses module
class TimeProject
  include Mongoid::Document

  field :name, type: String
  field :project_code, type: String
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
  field :team, type: Array, default: []
  field :_id, type: String, default: -> { project_code }

  has_one :time_vendor, class_name: 'TimeVendor'
  has_one :time_client, class_name: 'TimeClient'
  has_many :time_project_tasks, class_name: 'TimeProjectTask'
  # has_many :time_project_assignments, class_name: 'TimeProjectAssignment'
  has_many :timesheets, class_name: 'Timesheet'
end