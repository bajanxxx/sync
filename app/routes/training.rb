module Sync
  module Routes
    class Training < Base
      %w(/training /training/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      # Render training home page for admin, trainer and trainee
      get '/training' do
        ### ADMIN PORTAL
        if @user.owner? || @user.administrator?
          erb :training_admin_portal, locals: {
              training_tracks: TrainingTrack.all,
              users: Consultant.all,
              trainers: Trainer.all,
              slack_integrations: TrainingSlackIntegration.all
          }
        ### TRAINER PORTAL
        elsif @user.trainer?
          trainer = Trainer.find(@session_username)
          if trainer
            topics_assigned = []
            teams = []
            trainer.trainer_topics.map do |_tt|
              track = TrainingTrack.find(_tt.track)
              teams << _tt.team
              topics_assigned << {
                  track: track,
                  topic: track.training_topics.find(_tt.topic),
                  team: _tt.team
              }
            end

            erb :trainer_portal, locals: {
                training_tracks: TrainingTrack.all.entries,
                trainer: trainer,
                topics_assigned: topics_assigned,
                notifications: TrainingNotification.where(
                    destination: @session_username,
                    :created_at.gt => (Date.today-30) ,
                    :team.in => teams
                ).order_by(:created_at => 'desc')
            }
          else
            erb :trainer_portal_no_access
          end
        elsif @user.consultant?
          erb :training_consultant_portal, locals: {
            training_tracks: TrainingTrack.all.entries
          }
        else
          ### TRAINEE PORTAL
          consultant = Consultant.find(@session_username)
          if consultant.team.nil?
            erb :trainee_portal_noaccess
          else
            # progress
            # calculate progress of this user
            self_progress = build_training_progress(consultant)
            team_progress = Hash.new { |hash, key| hash[key] = {} }
            Consultant.where(team: consultant.team).ne(email: @session_username).each do |member|
              team_progress[member.email.to_sym] = build_training_progress(member)
            end

            erb :trainee_portal, locals: {
                consultant: consultant,
                training_tracks: TrainingTrack.all.entries,
                self_progress: self_progress,
                team_progress: team_progress,
                # TODO: Group re-submissions
                notifications: TrainingNotification.where(
                    destination: @session_username,
                    :created_at.gt => (Date.today-30)
                ).order_by(:created_at => 'desc')
            }
          end
        end
      end

      # Associates trainer to a specific track and team, so that trainer can get notifications and class progress
      post '/training/trainer/associate' do
        trainer_email = params[:temail]
        tt = params[:ttrack]
        track_code = tt.split('|').first
        topic_code = tt.split('|').last
        tteam = params[:tteam]
        tdomain = params[:tdomain]

        success = true
        message = "Successfully assigned trainer to track: #{track_code} (topic: #{topic_code})"

        if tdomain.upcase !~ /US|EU|IN/
          success = false
          message = 'Domain not properly formatted, possible values: US, EU, IN.'
          return { success: success, msg: message }.to_json
        end

        # only make this user a trainer or admin if the user is not an admin or owner
        user = User.find(trainer_email)
        unless user.administrator? or user.owner?
          User.find(trainer_email).role.update_attribute(:name, 'trainer')
        end
        if Trainer.find(trainer_email).nil?
          Trainer.create(email: trainer_email)
        end

        trainer = Trainer.find(trainer_email)

        # associate a trainer to a topic
        trainer.trainer_topics.create(
            track: TrainingTrack.find_by(code: track_code).id,
            topic: TrainingTrack.find_by(code: track_code).training_topics.find_by(code: topic_code).id,
            domain: tdomain,
            team: tteam
        )

        { success: success, msg: message }.to_json
      end

      post '/training/trainer/disassociate/:temail/:track_id/:topic_id' do |temail, track_id, topic_id|
        success = true
        message = "Successfully removed trainer from track: #{track_id} (topic: #{topic_id})"

        trainer = Trainer.find(temail)
        trainer.trainer_topics.find_by({track: track_id, topic: topic_id}).delete

        flash[:info] = message

        { success: success, msg: message }.to_json
      end

      post '/training/slack_integrations' do
        team = params[:team]
        domain = params[:domain]

        success = true
        message = "Successfully created slack integration for team: #{team} (domain: #{domain})"

        if team.empty? || domain.empty?
          success = false
          message = 'Params cannot be empty'
          return { success: success, msg: message }.to_json
        end

        TrainingSlackIntegration.create(
          team: team,
          domain: domain
        )

        { success: success, msg: message }.to_json
      end

      # Trainer's page to track class notifications and progress
      get '/training/trainer/track/:trackid/topic/:topicid/team/:teamid' do |trackid, topicid, teamid|
        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)

        # Build requests that needs approval from trainer
        project_submissions = project_submissions_for_topic(topic, teamid)
        assignment_submissions = Hash.new { |hash, key| hash[key] = {} }
        topic.training_sub_topics.each do |sub_topic|
          assignment_submissions[sub_topic.id] = {
              name: sub_topic.name,
              assignments: assignment_submissions_for_sub_topic(sub_topic, teamid)
          }
        end
        # get rid of the sub_topics which don't have any assignment submissions
        assignment_submissions.keys.each do |_stopic|
          assignment_submissions[_stopic][:assignments].keys.each do |_assignmentid|
            assignment_submissions[_stopic][:assignments].delete(_assignmentid) if ( assignment_submissions[_stopic][:assignments][_assignmentid].keys - [:name, :heading] ).empty?
          end
        end
        # get rid of the sub_topics which don't have any assignments
        assignment_submissions.keys.each do |_stopic|
          assignment_submissions.delete(_stopic) if assignment_submissions[_stopic][:assignments].empty?
        end

        # Build overall team progress
        team_progress = Hash.new { |hash, key| hash[key] = {} }
        Consultant.where(team: teamid).each do |member|
          team_progress[member.email.to_sym] = build_training_progress(member)
        end

        erb :trainer_topic_overview, locals: {
            track: track,
            topic: topic,
            teamid: teamid,
            team_progress: team_progress,
            project_submissions: project_submissions,
            assignment_submissions: assignment_submissions
        }
      end
    end
  end
end