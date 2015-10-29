class TrainingTopic
  include Mongoid::Document

  # name of the topic (ex: Hadoop, Spark, Cassandra)
  field :name, type: String
  field :code, type: String
  # who manages the content (email address)
  field :contact, type: String

  belongs_to :training_track
  has_many :training_sub_topics
end
