module Sync
  module Routes
    class TrainingIntegrations < Base
      # slack integrations main page
      get '/training/track/:trackid/integrations/slack/:domain/:team' do |trackid, domain, team|
        protected!

        track = TrainingTrack.find(trackid)
        erb :training_track_team_slack, locals: {
            track: track,
            domain: domain,
            team: team,
            default_users: @settings[:default_slack_users],
            team_users: Consultant.where(team: team, domain: domain),
            trainers: Trainer.all,
            preqs: track.training_topics.where(category: 'P').asc(:order),
            core: track.training_topics.where(category: 'C').asc(:order),
            adv: track.training_topics.where(category: 'A').asc(:order),
            opt: track.training_topics.where(category: 'O').asc(:order)
        }
      end

      # creates a slack group for a training topic and for specific team
      post '/training/track/:trackid/topic/:topicid/integrations/slack/:domain/:team/create' do |trackid, topicid, domain, team|
        group_name = params[:groupname]

        success = true
        message = 'Successfully created slack group'

        if group_name.length > 21
          success = false
          message = 'Group name should not exceed 21 characters'
        end

        if success
          topic = TrainingTopic.find(topicid)

          Slack.configure do |config|
            config.token = @settings[:slack_admin_user_api_token]
          end

          client = Slack::Web::Client.new

          if client.auth_test['ok']
            group = client.groups_list['groups'].detect { |g| g['name'] == group_name }
            if group
              # group exists
              success = false
              message = "Group with name: #{group_name} already exists. This group will be used for notifications."
              group_doc = topic.slack_groups.find_or_create_by(group_id: group['id'])
              group_doc.update_attributes(name: group_name, team: team, domain: domain)
            else
              # create group and return its id
              groupid = client.groups_create(name: group_name)['group']['id']
              # client.channels_setPurpose(channel: groupid, purpose: "Training updates, discussion for topic: #{topic.name}")
              topic.slack_groups.create(group_id: groupid, name: group_name, team: team, domain: domain)
            end
          else
            # failed to authenticate
            success = false
            message = 'Unable to authenticate with Slack'
          end
        end

        { success: success, msg: message }.to_json
      end

      # invites users to a slack group
      post '/training/track/:trackid/topic/:topicid/integrations/slack/:domain/:team/users/invite' do |trackid, topicid, domain, team|

        if params[:users].nil? || params[:users].empty?
          success = false
          message = 'Users cannot be empty'
          return { success: success, msg: message }.to_json
        end

        users = (params[:users] + @settings[:default_slack_users]).uniq
        bots = @settings[:default_slack_bots]

        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        group_name = topic.slack_groups.find_by(team: team, domain: domain).name

        success = true
        message = "Scheduled inviting users #{users.join(',')} to group #{group_name}."

        Delayed::Job.enqueue(
            SlackAssociateUsersToTopic.new(
                @settings[:slack_admin_user_api_token],
                track,
                topic,
                users,
                bots,
                group_name,
                @settings
            ),
            queue: 'slack_associate_users',
            priority: 10,
            run_at: 1.seconds.from_now
        )

        flash[:info] = message

        { success: success, msg: message }.to_json
      end
    end
  end
end