# Job document encapsulated using mongoid
# Usage: Job.create(:url => )
class Job
  include Mongoid::Document
  include Mongoid::Search

  field :search_term, type: String
  field :source,      type: String # Specify what the source is DICE, INDEED
  field :url,         type: String
  field :date_posted, type: Date
  field :title,       type: String
  field :company,     type: String
  field :location,    type: String
  field :skills,      type: Array
  field :emails,      type: Array
  field :phone_nums,  type: Array
  field :read,        type: Boolean, default: false # specify whether a job posting has been read previously
  field :hide,        type: Boolean, default: false # specify whether a user want this post to be hidden
  field :desc,        type: String
  field :trigger,     type: Array # possible triggers => [ 'SEND_TO_VENDOR', 'SEND_TO_CONSULTANT', 'CHECK_LATER', 'APPLY' ]
  field :link_active, type: Boolean, default: true # specify whether a job posting link is active or not

  index({ url: 1 }, { unique: true, name: "url_index" })

  search_in :title, :company, :location, :skills, :emails
  has_many :applications, class_name: 'Application'
end
