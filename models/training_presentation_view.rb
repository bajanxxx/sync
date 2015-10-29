class TrainingPresetationView
  include Mongoid::Document

  field :track, type: String
  field :topic, type: String
  field :subtopic, type: String
  field :consultant, type: String
  field :viewed_at, type: DateTime, default: DateTime.now
end