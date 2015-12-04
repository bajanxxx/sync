require 'slack-ruby-client'

class SlackGroupNotification < Struct.new(:api_token, :group_name, :pretext, :title, :title_link, :body, :color, :fields)
  def perform
    # Configure slack client
    Slack.configure do |config|
      config.token = api_token
    end

    client = Slack::Web::Client.new
    if client.auth_test['ok']
      # find or create group by its name
      group_id = find_group(client, group_name)
      if group_id
        slack_formatted_message(client, group_id, pretext, title, title_link, body, color, fields)
        # client.chat_postMessage(channel: group_id, text: "<!channel> #{message}", as_user: true)
      else
        log "Cannot send slack notification as the group with name #{group_name} is non-existent. OR may be you haven't invited sync bot user to the group."
      end
    else
      # failed to authenticate
      raise StandardError.new("Unable to authenticate with Slack")
    end
  end

  def success
    log "Successfully sent out slack notification to group #{group_name}"
  end

  def failure
    log "Failed sending slack notification to group #{group_name}"
  end

  def max_attempts
    3
  end

  # helper methods
  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end

  def find_group(client, group_name)
    group = client.groups_list['groups'].detect { |g| g['name'] == group_name }
    if group
      group['id']
    else
      nil
    end
  end

  def slack_formatted_message(client, channelid, pretext, title, title_link, body, color, fields = [])
    client.chat_postMessage(
      channel: channelid,
      as_user: true,
      attachments: [
        {
          fallback: "#{title} - #{title_link}",
          pretext: pretext,
          title: title,
          title_link: title_link,
          text: body,
          color: color,
          fields: fields
        }
      ]
    )
  end
end