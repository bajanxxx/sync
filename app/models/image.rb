class Image
  include Mongoid::Document

  field :name, type: String

  mount_uploader :image, ImageUploader
end