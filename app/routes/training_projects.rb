module Sync
  module Routes
    class TrainingProjects < Base
      # Create a new project for a specified topic of a track
      post '/training/track/:trackid/topic/:topicid/project' do |trackid, topicid|
        success    = true
        message    = 'Successfully added project'

        topic = TrainingTopic.find(topicid)
        heading = params[:heading]
        description = params[:description]
        athenaeumlink = params[:athenaeumlink]

        if !athenaeumlink.empty? && !athenaeumlink.start_with?('https://cloudwick.atlassian.net')
          success = false
          message = "description link should start with 'https://cloudwick.atlassian.net'"
        end

        if success
          project_num = topic.training_projects.count.to_i + 1

          topic.training_projects.create(
              name: "Project \##{project_num}",
              heading: heading,
              description: description,
              description_link: athenaeumlink,
              created_by: @user.name
          )
        end

        { success: success, msg: message }.to_json
      end

      post '/training/track/:trackid/topic/:topicid/project/:projectid/delete' do |trackid, topicid, projectid|
        topic = TrainingTopic.find(topicid)
        project = topic.training_projects.find(projectid)

        # TODO: throw error if user wants to delete if there submissions
        project.training_project_submissions.delete_all
        project.delete
      end

      # Update project contents
      post '/training/track/:trackid/topic/:topicid/project/:projectid/update' do |trackid, topicid, projectid|
        success    = true
        message    = 'Successfully updated project'

        topic = TrainingTopic.find(topicid)
        heading = params[:heading]
        description = params[:description]
        athenaeumlink = params[:athenaeumlink]

        if !athenaeumlink.empty? && !athenaeumlink.start_with?('https://cloudwick.atlassian.net')
          success = false
          message = "description link should start with 'https://cloudwick.atlassian.net'"
        end

        if success
          project = topic.training_projects.find(projectid)
          edited_at = DateTime.now
          edited_by = @user.name
          project.update_attributes(
              heading: heading,
              description: description,
              description_link: athenaeumlink,
              last_edited_at: edited_at,
              last_edited_by: edited_by
          )
          project.push(:edit_history, {name: edited_by, at: edited_at})
        end

        { success: success, msg: message }.to_json
      end

      # Submit project by consultant
      post '/training/track/:trackid/topic/:topicid/project/:projectid/submit' do |trackid, topicid, projectid|
        success    = true
        message    = 'Successfully updated project'

        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        user = Consultant.find(@session_username)

        submission_link = params[:submissionlink]

        unless TrainerTopic.find_by(
            track: track.id,
            topic: topic.id,
            team: user.team)
          success = false
          message = 'Sorry there is no trainer yet associated with this topic, hence you cannot submit the project'
          return { success: success, msg: message }.to_json
        end

        unless submission_link.start_with?("http://git.cloudwick.com/team#{user.team}_#{user.domain.downcase}/#{user.id.split('@').first}")
          success = false
          message = "submission link should start with 'http://git.cloudwick.com/team#{user.team}_#{user.domain.downcase}/#{user.id.split('@').first}'"
        end

        if success
          project = topic.training_projects.find(projectid)
          trainer_email = TrainerTopic.find_by(track: trackid, topic: topicid, team: user.team).trainer_id

          project_submission = project.training_project_submissions.find_by(
              consultant_id: @session_username
          )

          if project_submission # re-submission
            project_submission.update_attributes(
                submission_link: submission_link,
                resubmission: true,
                status: 'SUBMITTED'
            )
            message = "Re-submitted project: '#{project.name}' from topic: '#{topic.name}'"

            # Resubmission should only be notified to user not to all users
            TrainingNotification.create(
                originator: user.email,
                name: "#{user.first_name} #{user.last_name}",
                broadcast: 'U',
                destination: user.email,
                team: user.team,
                type: 'PROJECT',
                sub_type: 'RESUBMISSION',
                track: trackid,
                topic: topicid,
                submission_link: submission_link,
                project_id: projectid,
                message: message
            )

            # Trainer should be notified about the re-submission
            Delayed::Job.enqueue(
                SlackUserNotification.new(
                    @settings[:slack_sync_bot_api_token],
                    trainer_email,
                    {
                        pretext: 'Notification from Cloudwick Sync',
                        title: "Project Re-Submission made by #{user.first_name} #{user.last_name}",
                        title_link: 'http://sync.cloudwick.com/training',
                        body: "#{user.first_name} #{user.last_name} has made a project (#{project.name}) re-submission from topic: '#{topic.name}'. Please review the project submission by clicking the above link.",
                        color: 'info',
                        fields: [
                            {title: 'Submitted by', value: "#{user.first_name} #{user.last_name}", short: true },
                            {title: 'Submitted', value: DateTime.now.strftime('%d/%m/%Y'), short: true },
                            {title: 'Type', value: 'Re-submission', short: true}
                        ]
                    }
                ),
                queue: 'slack_notifications',
                priority: 10,
                run_at: 1.seconds.from_now
            )
          else # first time submission
            project.training_project_submissions.create(
                consultant_id: @session_username,
                submission_link: submission_link,
                status: 'SUBMITTED'
            )

            # create notification for everyone in the team
            Consultant.where(team: user.team).each do |consultant|
              TrainingNotification.create(
                  originator: user.email,
                  name: "#{user.first_name} #{user.last_name}",
                  destination: consultant.id,
                  broadcast: 'T',
                  team: user.team,
                  type: 'PROJECT',
                  sub_type: 'SUBMISSION',
                  track: trackid,
                  topic: topicid,
                  submission_link: submission_link,
                  project_id: projectid,
                  message: "Submitted project: '#{project.name}' from topic: '#{topic.name}'"
              )
            end
            Delayed::Job.enqueue(
                SlackGroupNotification.new(
                    @settings,
                    @settings[:slack_sync_bot_api_token],
                    "team#{user.team}_#{track.code.downcase}_#{topic.code.downcase}",
                    # "'#{user.first_name} #{user.last_name}' submitted '#{project.name}' from topic: '#{topic.name}'."
                    {
                        pretext: 'Notification from Cloudwick Sync',
                        title: "Project Submission made by #{user.first_name} #{user.last_name}",
                        title_link: 'http://sync.cloudwick.com/training',
                        body: "#{user.first_name} #{user.last_name} has made a project (#{project.name}) submission from topic: '#{topic.name}'.",
                        color: 'primary',
                        fields: [
                            {title: 'Submitted by', value: "#{user.first_name} #{user.last_name}", short: true },
                            {title: 'Submitted', value: DateTime.now.strftime('%d/%m/%Y'), short: true }
                        ]
                    }
                ),
                queue: 'slack_notifications',
                priority: 10,
                run_at: 1.seconds.from_now
            )
            # create a notification for trainer
            TrainingNotification.create(
                originator: user.email,
                name: "#{user.first_name} #{user.last_name}",
                destination: trainer_email,
                broadcast: 'T',
                team: user.team,
                type: 'PROJECT',
                sub_type: 'SUBMISSION',
                track: trackid,
                topic: topicid,
                submission_link: submission_link,
                project_id: projectid,
                message: "Submitted project: '#{project.name}' from topic: '#{topic.name}'"
            )
            # send a slack notification to the trainer
            Delayed::Job.enqueue(
                SlackUserNotification.new(
                    @settings[:slack_sync_bot_api_token],
                    trainer_email,
                    {
                        pretext: 'Notification from Cloudwick Sync',
                        title: "Project Submission made by #{user.first_name} #{user.last_name}",
                        title_link: 'http://sync.cloudwick.com/training',
                        body: "#{user.first_name} #{user.last_name} has made a project (#{project.name}) submission from topic: '#{topic.name}'. Please review the project submission by clicking the above link.",
                        color: 'primary',
                        fields: [
                            {title: 'Submitted by', value: "#{user.first_name} #{user.last_name}", short: true },
                            {title: 'Submitted', value: DateTime.now.strftime('%d/%m/%Y'), short: true }
                        ]
                    }
                ),
                queue: 'slack_notifications',
                priority: 10,
                run_at: 1.seconds.from_now
            )
          end
        end

        { success: success, msg: message }.to_json
      end

      post '/training/track/:trackid/topic/:topicid/project/:projectid/:consultantid/approve' do |trackid, topicid, projectid, consultantid|
        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        project = topic.training_projects.find(projectid)

        trainee = Consultant.find(consultantid)
        trainer = Consultant.find(@session_username)

        project.training_project_submissions.find_by(
            consultant_id: consultantid
        ).update_attributes(
            status: 'APPROVED'
        )
        # create notification for everyone in the team
        Consultant.where(team: trainee.team).each do |consultant|
          TrainingNotification.create(
              originator: @session_username,
              name: "#{trainer.first_name} #{trainer.last_name}",
              broadcast: 'T',
              destination: consultant.id,
              team: trainee.team,
              type: 'PROJECT',
              sub_type: 'APPROVAL',
              track: trackid,
              topic: topicid,
              project_id: projectid,
              message: "Approved #{trainee.first_name} #{trainee.last_name}'s project('#{project.name}') submission from topic: '#{topic.name}'"
          )
        end
        # Notify the user about the approval
        Delayed::Job.enqueue(
            SlackUserNotification.new(
                @settings[:slack_sync_bot_api_token],
                trainee.email,
                {
                    pretext: 'Notification from Cloudwick Sync',
                    title: "Your project submission was approved.",
                    title_link: 'http://sync.cloudwick.com/training',
                    body: "Your project (#{project.name}) submission from topic: '#{topic.name}' has been reviewed and got approved.",
                    color: 'success',
                    fields: [
                        {title: 'Approved by', value: "#{trainer.first_name} #{trainer.last_name}", short: true },
                        {title: 'Approved at', value: DateTime.now.strftime('%d/%m/%Y'), short: true }
                    ]
                }
            ),
            queue: 'slack_notifications',
            priority: 10,
            run_at: 1.seconds.from_now
        )

        flash[:info] = 'Successfully registered event, sent notification to trainee.'
      end

      post '/training/track/:trackid/topic/:topicid/project/:projectid/:consultantid/redo' do |trackid, topicid, projectid, consultantid|
        success = true
        message = "Successfully registered event, sent notification to trainee"

        reason = params[:reason]

        topic = TrainingTopic.find(topicid)
        project = topic.training_projects.find(projectid)

        trainee = Consultant.find(consultantid)
        trainer = Consultant.find(@session_username)

        project.training_project_submissions.find_by(
            consultant_id: consultantid
        ).update_attributes(
            status: 'REDO',
            redo_reason: reason
        )

        TrainingNotification.create(
            originator: @session_username,
            name: "#{trainer.first_name} #{trainer.last_name}",
            broadcast: 'U',
            destination: trainee.id,
            team: trainee.team,
            type: 'PROJECT',
            sub_type: 'REDO',
            track: trackid,
            topic: topicid,
            project_id: projectid,
            message: "Please review your project('#{project.name}') submission from topic: '#{topic.name}'. Notes from reviewer: #{reason}."
        )
        Delayed::Job.enqueue(
            SlackUserNotification.new(
                @settings[:slack_sync_bot_api_token],
                trainee.email,
                {
                    pretext: 'Notification from Cloudwick Sync',
                    title: 'Project Submission disapproved.',
                    title_link: 'http://sync.cloudwick.com/training',
                    body: "#{trainer.first_name} #{trainer.last_name} disapproved your '#{project.name}' submission from topic: '#{topic.name}'. Please review the project submission based on the comments/notes provided by trainer and re-submit it.",
                    color: 'warning',
                    fields: [
                        { title: 'Disapproved by', value: "#{trainer.first_name} #{trainer.last_name}", short: true },
                        { title: 'Disapproved on', value: DateTime.now.strftime('%d/%m/%Y'), short: true },
                        { title: 'Notes', value: reason }
                    ]
                }
            ),
            queue: 'slack_notifications',
            priority: 10,
            run_at: 1.seconds.from_now
        )

        flash[:info] = message

        { success: success, msg: message }.to_json
      end

    end
  end
end