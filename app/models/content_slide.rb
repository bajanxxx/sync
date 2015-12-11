class ContentSlide
  include Mongoid::Document

  # slide name (first, 1, 2, 3, .... n, last)
  field :name, type: String
  field :filename, type: String
  field :uploaded_date, type: DateTime
  field :filetype, type: String
  field :file_id, type: String

  belongs_to :training_sub_topic
end
