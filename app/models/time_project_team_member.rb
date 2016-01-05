class TimeProjectTeamMember
  include Mongoid::Document

  field :consultant, type: String # email_id of the consultant
  field :price, type: String

  belongs_to :time_project, class_name: 'TimeProject'
end