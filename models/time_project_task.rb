# Represents a project_task in TimeSheets & Expenses module
class TimeProjectTask
  include Mongoid::Document

  field :name, type: String
  field :hourly_rate, type: String, default: '0.00'
  field :billable?, type: Boolean, default: false

  belongs_to :time_project, class_name: 'TimeProject'
end