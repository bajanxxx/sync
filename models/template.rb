class Template
  include Mongoid::Document

  field :name, type: String
  field :subject, type: String
  field :content, type: String
end
