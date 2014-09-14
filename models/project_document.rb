class ProjectDocument
  include Mongoid::Document

  field :filename, type: String
  field :timestamp, type: String
  field :_id, type: String

  embedded_in :project, class_name: 'Project'
end
