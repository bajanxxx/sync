class Detail
  include Mongoid::Document
  include Mongoid::Versioning

  # keep at most 5 versions of a record
  max_versions 5

  field :trainings, type: Array, default: []
  field :certifications, type: Array, default: []
  field :current_company, type: String

  embeds_many :projects, class_name: 'Project'
  accepts_nested_attributes_for :projects
  belongs_to :consultant, class_name: 'Consultant'
end
