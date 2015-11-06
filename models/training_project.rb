class TrainingProject
  include Mongoid::Document

  # name of the assignment - auto-generated 'Project #1'
  field :name, type: String
  field :heading, type: String
  field :description, type: String, default: ''
  field :description_link, type: String, default: ''

  belongs_to :training_topic
  has_many :training_project_submissions
end
