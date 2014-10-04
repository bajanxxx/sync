class User
  include Mongoid::Document

  field :email,    type: String
  field :password, type: String
  field :admin,    type: Boolean, default: false
  field :lun,      type: String   # linux username
  field :lpwd,     type: String   # linux password
  field :pem,      type: String   # linux ssh private key
  field :pub,      type: String   # linux ssh public key
  field :fin,      type: String   # linux ssh fingerprint
  field :_id,      type: String, default: ->{ email }
end
