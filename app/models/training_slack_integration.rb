class TrainingSlackIntegration
  include Mongoid::Document

  field :team, type: Numeric
  field :domain, type: String
end