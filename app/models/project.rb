class Project
  include Mongoid::Document

  field :project_id, type: Integer
  field :name, type: String # name of the project
  field :_id, type: String, default: -> { name }
  field :client, type: String
  field :industry_vertical, type: String
  field :title, type: String
  field :current, type: Boolean, default: false # is this your current prject
  field :duration, type: Integer, default: 0 # how many months have you worked
  field :software, type: Array, default: [] # frameworks used in the project
  field :management_tools, type: Array, default: [] # management tools used
  field :commercial_support, type: Array, default: []
  field :point_of_contact, type: Array, default: []

  embedded_in :detail, class_name: 'Detail'
  embeds_many :usecases, class_name: 'UseCase'
  accepts_nested_attributes_for :usecases
  embeds_many :illustrations, class_name: 'Illustration'
  accepts_nested_attributes_for :illustrations
  embeds_many :projectdocuments, class_name: 'ProjectDocument'
  accepts_nested_attributes_for :projectdocuments
end
