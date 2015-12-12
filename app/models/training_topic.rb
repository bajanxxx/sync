class TrainingTopic
  include Mongoid::Document

  # name of the topic (ex: Hadoop, Spark, Cassandra)
  field :name, type: String
  # short code for the topic, unique name for the topic (should be <=10 chars), will be used for slack group name
  field :code, type: String
  # who manages the content (email address)
  field :contact, type: String
  # category - prerequisite (P), core (C), advanced (A), others (O)
  field :category, type: String
  # order of the topic by category
  field :order, type: Integer, default: 0

  belongs_to :training_track
  has_many :training_sub_topics
  has_many :training_projects
  has_many :training_resources
  has_many :slack_groups
end
