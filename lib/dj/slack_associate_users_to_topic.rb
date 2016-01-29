require 'slack-ruby-client'

class SlackAssociateUsersToTopic < Struct.new(:api_token, :track, :topic, :users, :bots, :group_name, :settings)
  def perform
    # Configure slack client
    Slack.configure do |config|
      config.token = api_token
    end

    client = Slack::Web::Client.new
    if client.auth_test['ok']
      group_id = find_or_create_group(client, group_name, "Training updates, discussion for topic: #{topic.name}")
      add_users_to_group(client, group_id, users)
      add_bots_to_group(client, group_id, bots)
    else
      # failed to authenticate
      raise StandardError.new('Unable to authenticate with Slack')
    end
  end

  def success
    log "Successfully associated users #{users.join(",")} to track #{track.name}"
  end

  def failure
    log "Failed associating users #{users.join(",")} to track #{track.name}"
  end

  def max_attempts
    3
  end

  # helper methods
  def find_or_create_group(client, group_name, purpose)
    group = client.groups_list['groups'].detect { |g| g['name'] == group_name }
    if group
      # group exists return the group_id
      group['id']
    else
      # create group and return its id
      groupid = client.groups_create(name: group_name)['group']['id']
      log "Successfully created group with name: #{group_name}"
      # set_group_purpose(client, groupid, purpose)
      groupid
    end
  end

  def set_group_purpose(client, groupid, purpose)
    client.groups_setpurpose(channel: groupid, purpose: purpose)
  end

  def add_user_to_group(client, groupid, user)
    group_members = client.groups_info(channel: groupid)['group']['members']
    userid = get_userid_from_email(client, user)
    if userid
      unless group_members.include?(userid)
        log "Inviting user: #{user} to group: #{groupid}"
        client.groups_invite(channel: groupid, user: userid)
        topic.slack_groups.find_by(name: group_name).add_to_set(:members, user)
      else
        topic.slack_groups.find_by(name: group_name).add_to_set(:members, user)
      end
    else
      notify_user(user)
    end
  end

  def add_bot_to_group(client, groupid, botname)
    group_members = client.groups_info(channel: groupid)['group']['members']
    botid = get_bot_id(client, botname)
    if botid
      unless group_members.include?(botid)
        log "Inviting bot: #{botname} to group: #{groupid}"
        client.groups_invite(channel: groupid, user: botid)
        topic.slack_groups.find_by(name: group_name).add_to_set(:bots, botname)
      end
    end
  end

  def add_users_to_group(client, group_id, members)
    members.each do |member|
      add_user_to_group(client, group_id, member)
    end
  end

  def add_bots_to_group(client, group_id, members)
    members.each do |member|
      add_bot_to_group(client, group_id, member)
    end
  end

  def get_userid_from_email(client, user_email)
    user = client.users_list['members'].detect { |u| u['profile']['email'] == user_email }
    user ? user['id'] : nil
  end

  def get_bot_id(client, botname)
    bot = client.users_list['members'].detect { |u| u['name'] == botname }
    bot ? bot['id'] : nil
  end

  def notify_user(user_email)
    log "User does not exist #{user_email} in Slack."
    email_body = <<EOBODY
      <p>Hello,</p>
      <p>Seems like you haven't yet signed into Slack. Admin has created a Slack discussion group for topic: #{topic.name}. Once signed in contact admin to invite you to that group.</p>
      <br/>
      <p><em><strong>Note</strong>: This email is generated by cloudwick sync portal. If you have received this email by error please contact <a href="mailto:admin@cloudwick.com?Subject=Sync%20Misplaced%20Email">admin</a>.</em></p>
      <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
    Pony.mail(
      from: 'Cloudwick Sync' + "<" + settings[:email] + ">",
      to: user_email,
      subject: "Requires logging into Slack",
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

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end