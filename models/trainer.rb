class Trainer
  include Mongoid::Document

  field :email, type: String
  
  field :_id, type: String, default: ->{ email }

  has_many :trainer_topics
end