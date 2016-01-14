require 'rubygems'
require 'bundler'

Bundler.require

# Setup $LOAD path
$: << File.expand_path('../', __FILE__)
$: << File.expand_path('../lib', __FILE__)

# Require base
require 'sinatra/base'

Dir['lib/**/*.rb'].sort.each { |file| require file }

require 'app/extensions'
require 'app/extensions/flash'
require 'app/models'
require 'app/helpers'
require 'app/routes'

# Global app logger
Log = Logger.new(File.expand_path('../log/app.log', __FILE__))

# DelayedJob wants us to be on rails, so it looks for stuff
# in the rails namespace -- so we emulate it a bit
module Rails
  class << self
    attr_accessor :logger
  end
end
Rails.logger = Log

# this is used by DJ to guess where tmp/pids is located (default)
RAILS_ROOT = File.expand_path('..', __FILE__)

# Configure DelayedJob
Delayed::Worker.destroy_failed_jobs = true
Delayed::Worker.sleep_delay = 5
Delayed::Worker.max_attempts = 5
Delayed::Worker.max_run_time = 15.minutes

module Sync
  class App < Sinatra::Base
    configure do
      # Load configuration file
      Settings.load!('config/config.yml')

      enable :logging
      enable :dump_errors

      disable :method_override
      disable :static

      set :protection, :except => [ :session_hijacking ]

      # set :erb, escape_html: true

      enable :sessions
      set :sessions,
          httponly: true, # tells browser that cookies can only change from the server and not from the browser - this does not eliminate cross site tracking
          # secure: production?, # protects from MITM attacks, sends cookies over https. TODO: requires SSL/TLS enabled web server
          expire_after: 5.years
      
      set :session_secret, 'super secret'

      # Load OmniAuth - for google single sign on
      use OmniAuth::Builder do
        provider :google_oauth2,
                 Settings.public_send(Sinatra::Base.settings.environment)[:google_key],
                 Settings.public_send(Sinatra::Base.settings.environment)[:google_secret], {
            prompt: 'select_account',
            image_aspect_ratio: 'square',
            image_size: 200,
            provider_ignores_state: true,
            skip_jwt: true
        }
      end
    end

    configure :development, :staging do
      # database.loggers << Logger.new(STDOUT)
      Mongoid.load!('config/mongoid.yml', :development)
    end

    configure :production do
      Mongoid.load!('config/mongoid.yml', :production)
    end

    not_found do
      status 404
      'The path you are trying to access is not found.'
    end

    use Rack::Deflater
    use Rack::Standards

    #
    # Register all routes:
    #
    use Sync::Routes::Static

    unless settings.production?
      use Sync::Routes::Assets
    end

    use Sync::Routes::Index
    use Sync::Routes::Users
    use Sync::Routes::Common
    use Sync::Routes::Consultants
    use Sync::Routes::ConsultantProjects
    use Sync::Routes::Jobs
    use Sync::Routes::Campaigns
    use Sync::Routes::Customers
    use Sync::Routes::Vendors
    use Sync::Routes::Documents
    use Sync::Routes::AirTickets
    use Sync::Routes::Certifications
    use Sync::Routes::CloudServers
    use Sync::Routes::Timesheets
    use Sync::Routes::TimesheetProjects
    use Sync::Routes::TimesheetVendors
    use Sync::Routes::TimesheetClients
    use Sync::Routes::TimesheetReports
    use Sync::Routes::Training
    use Sync::Routes::TrainingTracks
    use Sync::Routes::TrainingTopics
    use Sync::Routes::TrainingProjects
    use Sync::Routes::TrainingSubTopics
    use Sync::Routes::TrainingAssignments
    use Sync::Routes::TrainingIntegrations
  end
end

include Sync::Models
