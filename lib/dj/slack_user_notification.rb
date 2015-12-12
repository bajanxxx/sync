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
      #client.chat_postMessage(channel: channel_id, text: "<@#{uname}> #{message}", as_user: true)
      slack_formatted_message(
          client,
          channel_id,
          uname,
          message[:pretext],
          message[:title],
          message[:title_link],
          message[:body],
          message[:color],
          message[:fields]
      )
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

  def color_hex(name)
    case name
      when 'primary'  # blue
        '#3498db'
      when 'success'  # green
        '#2ecc71'
      when 'info'     # purple
        '#9b59b6'
      when 'warning'  # orange
        '#e67e22'
      when 'danger'   # red
        '#e74c3c'
      else            # default
        '#95a5a6'
    end
  end

  # Example:
  # slack_formatted_message(
  #   client,
  #   '#random',
  #       'New ticket from Andrea Lee',
  #       "Ticket #1943: Can't reset my password",
  #       'https://groove.hq/path/to/ticket/1943',
  #       'Help! I tried to reset my password but nothing happened!',
  #       color_hex('default'),
  #       [
  #           { title: "Assigned to", value: "John Doe", short: true },
  #           { title: "Priority", value: "High", short: true }
  #       ]
  #   )
  #
  #
  def slack_formatted_message(client, channelid, uname, pretext, title, title_link, body, color, fields = [])
    client.chat_postMessage(
        channel: channelid,
        as_user: true,
        attachments: [
            {
                fallback: "#{title} - #{title_link}",
                pretext: "<@#{uname}> #{pretext}",
                title: title,
                title_link: title_link,
                text: body,
                color: color_hex(color),
                fields: fields
            }
        ]
    )
  end
end