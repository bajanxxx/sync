class CloudRequest
  include Mongoid::Document

  field :requester, type: String
  field :purpose, type: String
  # specify whether a request is active (that means if the user has not deleted it)
  field :active?, type: Boolean, default: false
  # specify whether a request is approved by admin
  field :approved?, type: Boolean, default: false
  # specify whether a reqest once approved has been processed by the background job
  field :fulfilled?, type: Boolean, default: false
  # used to fix lock to check if a delayed job process is working on it
  field :lock?, type: Boolean, default: false
  # used to verify is the previous request failed because of connection issue
  field :connection_failed?, type: Boolean, default: false

  field :created_at, type: DateTime, default: DateTime.now
  field :approved_by, type: String
  field :approved_at, type: DateTime
  field :disapproved?, type: Boolean, default: false
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime

  has_many :cloud_instances
end
