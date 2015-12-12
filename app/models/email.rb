class Email
  include Mongoid::Document

  field :recipient, type: String
  field :sender, type: String
  field :subject, type: String
  field :from, type: String
  field :received, type: String
  field :stripped_text, type: String
  field :stripped_signature, type: String
  field :message_id, type: String # format: campaign_id@mailgun_domain
  field :campaign_id, type: String
  field :attachments_count, type: Integer

  has_many :attachments, class_name: 'Attachement'
end
