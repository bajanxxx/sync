module Sync
  module Routes
    class Base < Sinatra::Base
      configure do
        set :root, App.root
        set :views, 'app/views'

        disable :method_override
        disable :protection
        disable :static

        # Disable internal middleware for presenting errors as useful HTML pages
        set show_exceptions: false
        set raise_errors: false
        enable :use_code

        set :erb, layout_options: {views: 'app/views/layouts'}
      end

      register Extensions::Assets
      register Extensions::Auth
      register Sinatra::Flash
      # register Sinatra::JsonExceptions

      helpers Sinatra::ContentFor
      helpers Sync::Helpers::GridFs
      helpers Sync::Helpers::Campaign
      helpers Sync::Helpers::Training
      helpers Sync::Helpers::Openstack
      helpers Sync::Helpers::DateTime
      helpers Sync::Helpers::Sms

      before do
        @session_username = session_username
        @user = User.find(session_username) if session_username
        @settings = Settings._settings[Sinatra::Base.settings.environment]
        @email_regex = Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')
      end

      # The error handlers will only be invoked, however, if both the Sinatra
      # :raise_errors and :show_exceptions configuration options have been set to false.
      error do
        error_msg = request.env['sinatra.error']
        erb :error, :locals => { error_msg: error_msg }
      end

      error Moped::Errors::ConnectionFailure do
        error_msg = 'Cannot connect to the Mongo. Please notify the admin.'
        erb :error, :locals => { error_msg: error_msg }
      end
    end
  end
end