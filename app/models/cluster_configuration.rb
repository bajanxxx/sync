class ClusterConfiguration
  include Mongoid::Document

  field :type, type: String # prod, preprod
  field :nodes, type: Integer, default: 0
  field :hardware_type
  field :software, type: Array, default: []
  field :tools, type: Array, default: []
  field :bi_integration, type: Array, default: []
  field :db_integration, type: Array, default: []

  embedded_in :usecase, class_name: 'UseCase'
end
