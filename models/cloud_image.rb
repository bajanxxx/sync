class CloudImage
  include Mongoid::Document

  field :image_id, type: String
  field :os, type: String
  field :os_ver, type: String
  field :os_arch, type: String
  field :username, type: String

  field :_id, type: String, default: -> { image_id }
end
