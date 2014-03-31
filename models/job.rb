# Job document encapsulated using mongoid
# Usage: Job.create(:url => )
class Job
  include Mongoid::Document

  field :url,         type: String
  field :date_posted, type: Date
  field :title,       type: String
  field :company,     type: String
  field :location,    type: String
  field :skills,      type: Array
  field :emails,      type: Array
  field :phone_nums,  type: Array
end
