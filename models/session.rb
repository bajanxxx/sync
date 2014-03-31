class Session
  include Mongoid::Document

  field :username,   type: String
  field :session_id, type: String
  field :_id,        type: String, default: ->{ session_id }
end
