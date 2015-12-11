class TrainingProject
  include Mongoid::Document

  # name of the assignment - auto-generated 'Project #1'
  field :name, type: String
  field :heading, type: String
  field :description, type: String, default: ''
  field :description_link, type: String, default: ''
  field :created_by, type: String # name of the admin/trainer who created the project
  field :created_at, type: DateTime, default: DateTime.now
  field :edit_history, type: Array, default: []
  field :last_edited_at, type: DateTime
  field :last_edited_by, type: String

  belongs_to :training_topic
  has_many :training_project_submissions
end
