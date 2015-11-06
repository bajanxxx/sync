class TrainingNotification
  include Mongoid::Document

  # consultant id which is the point of origin of this notification
  field :originator, type: String
  # full user name
  field :name, type: String
  # broadcast level -> U - user, T - team, A - trainer and team
  field :broadcast, type: String
  # destination email address or id
  field :destination, type: String
  field :team, type: Integer
  # type of notification -> ASSIGNMENT, PROJECT, ACCESS
  field :type, type: String
  # sub-type of notification
  # access -> topic access granted, topic access requested
  # assignment -> SUBMISSION, RESUBMISSION, APPROVAL, REDO
  # project -> SUBMISSION, RESUBMISSION, APPROVAL, REDO
  # 
  field :sub_type, type: String
  # track and topic this notification belongs to
  field :track, type: String
  field :topic, type: String
  field :sub_topic, type: String
  # assignment or project submission/re-submission link, easy for trainer to find it
  field :submission_link, type: String
  field :project_id, type: String
  field :assignment_id, type: String
  # message of the notification
  field :message, type: String
  # when the notification was created
  field :created_at, type: DateTime, default: DateTime.now
end