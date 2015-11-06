class TrainingTopic
  include Mongoid::Document

  # name of the topic (ex: Hadoop, Spark, Cassandra)
  field :name, type: String
  # short code for the topic, unique name for the topic
  field :code, type: String
  # who manages the content (email address)
  field :contact, type: String
  # category - prerequisite (P), core (C), advanced (A), others (O)
  field :category, type: String

  belongs_to :training_track
  has_many :training_sub_topics
  has_many :training_projects
end
