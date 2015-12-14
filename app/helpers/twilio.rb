module Sync
  module Helpers
    module Sms
      def twilio
        Twilio::REST::Client.new(
            @settings[:twilio_account_sid],
            @settings[:twilio_auth_token]
        )
      end
    end
  end
end