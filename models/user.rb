class User
  include Mongoid::Document

  field :email,    type: String
  field :password, type: String
  field :admin,    type: Boolean, default: false
  field :_id,      type: String, default: ->{ email }
end
