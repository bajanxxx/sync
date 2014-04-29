class Email
  include Mongoid::Document

  field :recipient, type: String
  field :sender, type: String
  field :subject, type: String
  field :from, type: String
  field :recieved, type: String
  field :stripped_text, type: String
  field :stripped_signatures, type: String
  field :attachments_count, type: Integer

  has_many :attachments, class_name: 'Attachement'
end
