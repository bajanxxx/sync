class Thumbnail
  include Mongoid::Document

  field :name, type: String
  field :filename, type: String
  field :uploaded_date, type: DateTime
  field :filetype, type: String
  field :file_id, type: String
end
