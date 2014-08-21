class DocumentTemplate
  include Mongoid::Document

  field :name, type: String
  field :content, type: String
  field :type, type: String # type of template, OFFERLETTER, LEAVELETTER
end
