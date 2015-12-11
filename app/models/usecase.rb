class UseCase
  include Mongoid::Document

  field :name, type: String
  field :_id, type: String, default: -> { name }
  field :description, type: String

  embeds_many :requirements, class_name: 'Requirement'
  accepts_nested_attributes_for :requirements
  embeds_many :clusterconfigurations, class_name: 'ClusterConfiguration'
  accepts_nested_attributes_for :clusterconfigurations
  embedded_in :project, class_name: 'Project'
end
