require 'slack-ruby-client'

class SlackUserNotification < Struct.new(:api_token, :email, :message)
  def perform
    # Configure slack client
    Slack.configure do |config|
      config.token = api_token
    end

    client = Slack::Web::Client.new
    if client.auth_test['ok']
      # find the user by email address
      user = client.users_list['members'].detect { |u| u['profile']['email'] == email }
      uid = user['id']
      uname = user['name']
      # create an im channel to send direct message to
      channel_id = client.im_open(user: uid)['channel']['id']
      client.chat_postMessage(channel: channel_id, text: "<@#{uname}> #{message}", as_user: true)
    else
      # failed to authenticate
      raise StandardError.new("Unable to authenticate with Slack")
    end
  end

  def success
    log "Successfully sent out slack notification to #{email}"
  end

  def failure
    log "Failed sending slack notification to #{email}"
  end

  def max_attempts
    3
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end