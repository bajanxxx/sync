class Campaign
  include Mongoid::Document

  field :campaign_id, type: String
  field :campaign_name, type: String
  field :total_complained, type: Integer, default: 0
  field :total_clicked, type: Integer, default: 0
  field :total_opened, type: Integer, default: 0
  field :total_unsubscribed, type: Integer, default: 0
  field :total_bounced, type: Integer, default: 0
  field :total_sent, type: Integer, default: 0
  field :total_delivered, type: Integer, default: 0
  field :total_dropped, type: Integer, default: 0
  field :unique_opens, type: Integer, default: 0
  field :replies, type: Array, default: [] # Store id's of replies that we get back from mailgun
  field :active, type: Boolean, default: true # whether the campaign is active now or not

  field :_id, type: String, default: -> { campaign_id }
end
