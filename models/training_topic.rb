class TrainingTopic
  include Mongoid::Document

  # name of the topic (ex: Hadoop, Spark, Cassandra)
  field :name, type: String
  # who manages the content (email address)
  field :content_managed_by, type: String

  has_many :training_sub_topics
end
