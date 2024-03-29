class TrainingTrack
  include Mongoid::Document

  field :code, type: String # short code for this training track: 'DVOPS', should be unique
  field :name, type: String # track name example: 'DevOps', 'Data Engineer'
  field :image, type: String # image 400 x 400
  field :certifications, type: Array, default: [] # core certifications required for this track

  has_many :training_topics
end
