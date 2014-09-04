class Session
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include Mongoid::Timestamps::Updated

  field :username,   type: String
  field :session_id, type: String
  field :active,     type: Boolean
  field :_id,        type: String, default: ->{ session_id }
end
