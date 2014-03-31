class User
  include Mongoid::Document

  field :email,    type: String
  field :password, type: String
  field :_id,      type: String, default: ->{ email }
end
