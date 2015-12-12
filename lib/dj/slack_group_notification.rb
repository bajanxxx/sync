require 'slack-ruby-client'

class SlackGroupNotification < Struct.new(:settings, :api_token, :group_name, :message)
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
        # client.chat_postMessage(channel: group_id, text: "<!channel> #{message}", as_user: true)
        slack_formatted_message(
            client,
            group_id,
            message[:pretext],
            message[:title],
            message[:title_link],
            message[:body],
            message[:color],
            message[:fields]
        )
      else
        log "Cannot send slack notification as the group with name #{group_name} is non-existent."
        email_body = <<EOBODY
      <p>Hi Admin(s),</p>
      <p>Please create this group #{group_name} in Slack at the earliest, there are notifications being generated to this group.</p>
      <br/>
      <p><em><strong>Note</strong>: This email is generated by cloudwick sync portal. If you have received this email by error please contact <a href="mailto:admin@cloudwick.com?Subject=Sync%20Misplaced%20Email">admin</a>.</em></p>
      <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
        Pony.mail(
            from: 'Cloudwick Sync' + "<" + settings[:email] + ">",
            to: settings[:admin_group],
            subject: "Requires Slack Group #{group_name} to be created",
            headers: { 'Content-Type' => 'text/html' },
            body: email_body,
            via: :smtp,
            via_options: {
                address: settings[:smtp_address],
                port: settings[:smtp_port],
                enable_starttls_auto: true,
                user_name: settings[:email],
                password: settings[:password],
                authentication: :plain,
                domain: 'localhost.localdoamin'
            }
        )
      end
    else
      # failed to authenticate
      raise StandardError.new('Unable to authenticate with Slack')
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
                color: color_hex(color),
                fields: fields
            }
        ]
    )
  end
end
