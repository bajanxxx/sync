class TrainerTopic
  include Mongoid::Document

  field :track, type: String
  field :topic, type: String
  field :domain, type: String
  field :team, type: Integer
  field :created_at, type: DateTime, default: DateTime.now

  belongs_to :trainer
end