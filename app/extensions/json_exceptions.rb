module Sinatra
  module JsonExceptions
    def self.registered(app)
      app.set show_exceptions: false

      app.error do |err|
        Rack::Response.new(
            [{'error' => err.message}.to_json],
            500,
            {'Content-type' => 'application/json'}
        ).finish
      end
    end
  end
end