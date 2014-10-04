require 'clockwork'
require 'mongoid'
require 'delayed_job'
require 'delayed_job_mongoid'

require_relative '../settings'

require_relative '../../models/cloud_request'

#
# To start: bundle exec clockworkd --log-dir=log --log --clock=lib/clockwork/create_cloud_instances.rb start
# To stop: bundle exec clockworkd --clock=lib/clockwork/create_cloud_instances.rb stop
#

# Load mongoid
Mongoid.load!(File.expand_path('../../config/mongoid.yml', File.dirname(__FILE__)), :development)
# Load settings file
Settings.load!(File.expand_path('../../config/config.yml', File.dirname(__FILE__)))

module Clockwork
  # handler block is invoked everytime an event is triggered
  handler do |job, time|
    puts "Running #{job} at #{time}"
  end

  every(1.minute, 'cloud instance monitor') do
    perform
    # Delayed::Job.enqueue(CreateCloudServers.new(CloudRequest.all, File.expand_path('../log/delayed_job.log', File.dirname(__FILE__))))
  end

  def perform
    puts "Performing"
  end
end