class TrainingSubTopic
  include Mongoid::Document

  # name of the sub topic (ex: HDFS, MapReduce)
  field :name, type: String
  # NIL -> no file has been uploaded/linked
  # LINKED -> there is a pdf attached to this sub topic
  field :file, type: String, default: 'NIL'
  # NIL -> no content has yet been added to this topic
  # PROCESSING -> background dj is converting the pdf to images
  # SUCCESS -> dj process completed
  # FAILURE -> dj process failed converting pdf to images
  field :state, type: String, default: 'NIL'
  # specifies if any dj process is working on it
  field :lock?, type: Boolean, default: false

  belongs_to :training_topic
  has_one :pdf_file
  has_many :content_slides
end