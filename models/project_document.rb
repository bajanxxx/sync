class ProjectDocument
  include Mongoid::Document

  field :filename, type: String
  field :timestamp, type: String
  field :_id, type: String

  belongs_to :project, class_name: 'Project'
end
