class SlackGroup
  include Mongoid::Document

  # slack group id
  field :group_id, type: String
  # group name of slack
  field :name, type: String
  # members of the group
  field :members, type: Array, default: []
  # bots of the group
  field :bots, type: Array, default: []
  # team domain
  field :domain, type: String
  # team id
  field :team, type: Integer

  field :_id, type: String, default: -> { group_id }

  belongs_to :training_topic
end