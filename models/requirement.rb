class Requirement
  include Mongoid::Document

  field :requirement, type: String
  field :approch, type: String
  field :effort, type: String
  field :tools, type: Array, default: []
  field :resources, type: String
  field :insights, type: String

  embedded_in :usecase, class_name: 'UseCase'
end
