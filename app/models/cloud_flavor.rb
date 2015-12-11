class CloudFlavor
  include Mongoid::Document

  field :flavor_id, type: String
  field :flavor_name, type: String
  field :vcpus, type: String
  field :mem, type: String
  field :disk, type: String

  field :_id, type: String, default: -> { flavor_id }
end
