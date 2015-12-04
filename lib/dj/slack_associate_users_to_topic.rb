require 'slack-ruby-client'

class SlackAssociateUsersToTopic < Struct.new(:api_token, :track, :topic, :users, :bots, :group_name)
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
      raise StandardError.new("Unable to authenticate with Slack")
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
      return group['id']
    else
      # create group and return its id
      groupid = client.groups_create(name: group_name)['group']['id']
      log "Successfully created group with name: #{group_name}"
      set_group_purpose(client, groupid, purpose)
      return groupid
    end
  end

  def set_group_purpose(client, groupid, purpose)
    client.groups_setpurpose(channel: groupid, purpose: purpose)
  end

  def add_user_to_group(client, groupid, user)
    group_members = client.groups_info(channel: groupid)['group']['members']
    userid = get_userid_from_email(client, user)
    unless group_members.include?(userid)
      log "Inviting user: #{user} to group: #{groupid}"
      client.groups_invite(channel: groupid, user: userid)
      topic.slack_groups.find_by(name: group_name).add_to_set(:members, user)
    else
      topic.slack_groups.find_by(name: group_name).add_to_set(:members, user)
    end
  end

  def add_bot_to_group(client, groupid, botname)
    group_members = client.groups_info(channel: groupid)['group']['members']
    botid = get_bot_id(client, botname)
    unless group_members.include?(botid)
      log "Inviting bot: #{botname} to group: #{groupid}"
      client.groups_invite(channel: groupid, user: botid)
      topic.slack_groups.find_by(name: group_name).add_to_set(:bots, botname)
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
    client.users_list['members'].detect { |u| u['profile']['email'] == user_email }['id']
  end

  def get_bot_id(client, botname)
    client.users_list['members'].detect { |u| u['name'] == botname }['id']
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end