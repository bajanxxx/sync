module Sync
  module Helpers
    module Twilio
      def twilio
        Twilio::REST::Client.new(
            @settings[:twilio_account_sid],
            @settings[:twilio_auth_token]
        )
      end
    end
  end
end