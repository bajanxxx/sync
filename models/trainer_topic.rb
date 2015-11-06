class TrainerTopic
  include Mongoid::Document

  field :track, type: String
  field :topic, type: String
  field :team, type: Integer

  belongs_to :trainer
end