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
  # FAILED -> dj process failed converting pdf to images
  field :state, type: String, default: 'NIL'
  # estimated time to teach this sub-topic in minutes
  field :et, type: Integer, default: 0
  # specifies if any dj process is working on it
  field :lock?, type: Boolean, default: false
  # number of times users have started this topic presentation
  field :views, type: Integer, default: 0
  # order of the sub topic in the topic
  field :order, type: Integer, default: 0
  # references content
  field :references, type: String, default: ''
  # presentation resolution (dpi: dots per inch, default 72)
  field :density, type: Integer, default: 150

  belongs_to :training_topic
  has_one :pdf_file
  has_many :content_slides
  has_many :content_thumbnails
  has_many :training_assignments
  has_many :training_scratch_pads
end
