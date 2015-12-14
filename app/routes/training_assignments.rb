module Sync
  module Routes
    class TrainingAssignments < Base
      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/assignment' do |_, _, subtopicid|
        success    = true
        message    = 'Successfully added assignment'

        sub_topic = TrainingSubTopic.find(subtopicid)
        heading = params[:heading]
        description = params[:description]
        athenaeumlink = params[:athenaeumlink]

        if !athenaeumlink.empty? && !athenaeumlink.start_with?('https://cloudwick.atlassian.net')
          success = false
          message = "description link should start with 'https://cloudwick.atlassian.net'"
        end

        if success
          assignment_num = sub_topic.training_assignments.count.to_i + 1

          sub_topic.training_assignments.create(
              name: "Assignment \##{assignment_num}",
              heading: heading,
              description: description,
              description_link: athenaeumlink,
              created_by: @user.name
          )
        end

        { success: success, msg: message }.to_json
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/assignment/:assignmentid/delete' do |_, _, subtopicid, assignmentid|
        sub_topic = TrainingSubTopic.find(subtopicid)
        assignment = sub_topic.training_assignments.find(assignmentid)

        assignment.training_assignment_submissions.delete_all
        assignment.delete
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/assignment/:assignmentid/update' do |_, _, subtopicid, assignmentid|
        success    = true
        message    = 'Successfully updated assignment'

        sub_topic = TrainingSubTopic.find(subtopicid)
        heading = params[:heading]
        description = params[:description]
        athenaeumlink = params[:athenaeumlink]

        if !athenaeumlink.empty? && !athenaeumlink.start_with?('https://cloudwick.atlassian.net')
          success = false
          message = "description link should start with 'https://cloudwick.atlassian.net'"
        end

        if success
          assignment = sub_topic.training_assignments.find(assignmentid)
          edited_at = DateTime.now
          edited_by = @user.name
          assignment.update_attributes(
              heading: heading,
              description: description,
              description_link: athenaeumlink,
              last_edited_at: edited_at,
              last_edited_by: edited_by
          )
          assignment.push(:edit_history, {name: edited_by, at: edited_at})
        end

        { success: success, msg: message }.to_json
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/assignment/:assignmentid/submit' do |trackid, topicid, subtopicid, assignmentid|
        success    = true
        message    = 'Successfully updated assignment'

        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        sub_topic = TrainingSubTopic.find(subtopicid)
        user = Consultant.find(@session_username)

        submission_link = params[:submissionlink]

        unless TrainerTopic.find_by(
            track: track.id,
            topic: topic.id,
            team: user.team)
          success = false
          message = 'Sorry there is no trainer yet associated with this topic, hence you cannot submit the assignment'
          return { success: success, msg: message }.to_json
        end

        unless submission_link.start_with?('https://github.com/cloudwicklabs')
          success = false
          message = "submission link should start with 'https://github.com/cloudwicklabs'"
        end

        if success
          assignment = sub_topic.training_assignments.find(assignmentid)

          assignment_submission = assignment.training_assignment_submissions.find_by(
              consultant_id: @session_username
          )

          if assignment_submission # re-submission
            assignment_submission.update_attributes(
                submission_link: submission_link,
                resubmission: true,
                status: 'SUBMITTED'
            )

            # Resubmission should only be notified to user not to all users
            TrainingNotification.create(
                originator: user.email,
                name: "#{user.first_name} #{user.last_name}",
                broadcast: 'T',
                destination: user.email,
                team: user.team,
                type: 'ASSIGNMENT',
                sub_type: 'RESUBMISSION',
                track: trackid,
                topic: topicid,
                sub_topic: subtopicid,
                submission_link: submission_link,
                assignment_id: assignmentid,
                message: "Re-submitted assignment: '#{assignment.name}' of sub-topic: '#{sub_topic.name}' from topic: '#{topic.name}'"
            )

            # Resubmission should be notified to trainer as well
            Delayed::Job.enqueue(
                SlackUserNotification.new(
                    @settings[:slack_sync_bot_api_token],
                    trainer_email,
                    {
                        pretext: 'Notification from Cloudwick Sync',
                        title: "Assignment Re-submission made by #{user.first_name} #{user.last_name}",
                        title_link: 'http://sync.cloudwick.com/training',
                        body: "#{user.first_name} #{user.last_name} has made an assignment (#{assignment.name}) re-submission of sub-topic: '#{sub_topic.name}' from topic: '#{topic.name}'. Please review the assignment submission by clicking the above link.",
                        color: 'info',
                        fields: [
                            {title: 'Submitted by', value: "#{user.first_name} #{user.last_name}", short: true },
                            {title: 'Submitted at', value: DateTime.now.strftime('%d/%m/%Y'), short: true },
                            {title: 'Type', value: 'Re-Submission', short: true}
                        ]
                    }
                ),
                queue: 'slack_notifications',
                priority: 10,
                run_at: 1.seconds.from_now
            )
          else
            assignment.training_assignment_submissions.create(
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
                  type: 'ASSIGNMENT',
                  sub_type: 'SUBMISSION',
                  track: trackid,
                  topic: topicid,
                  sub_topic: subtopicid,
                  submission_link: submission_link,
                  assignment_id: assignmentid,
                  message: "Submitted assignment: '#{assignment.name}' of sub-topic: '#{sub_topic.name}' from topic: '#{topic.name}'"
              )
            end
            Delayed::Job.enqueue(
                SlackGroupNotification.new(
                    @settings,
                    @settings[:slack_sync_bot_api_token],
                    "team#{user.team}_#{track.code.downcase}_#{topic.code.downcase}",
                    # "'#{user.first_name} #{user.last_name}' submitted assignment '#{assignment.name}' from sub-topic: '#{sub_topic.name}' of topic: '#{topic.name}'."
                    {
                        pretext: 'Notification from Cloudwick Sync',
                        title: "Assignment Submission made by #{user.first_name} #{user.last_name}",
                        title_link: 'http://sync.cloudwick.com/training',
                        body: "#{user.first_name} #{user.last_name} has made an assignment (#{assignment.name}) submission of sub-topic: '#{sub_topic.name}' from topic: '#{topic.name}'.",
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
            trainer_email = TrainerTopic.find_by(track: trackid, topic: topicid, team: user.team).trainer_id
            TrainingNotification.create(
                originator: user.email,
                name: "#{user.first_name} #{user.last_name}",
                destination: trainer_email,
                broadcast: 'T',
                team: user.team,
                type: 'ASSIGNMENT',
                sub_type: 'SUBMISSION',
                track: trackid,
                topic: topicid,
                sub_topic: subtopicid,
                submission_link: submission_link,
                assignment_id: assignmentid,
                message: "Submitted assignment: '#{assignment.name}' of sub-topic: '#{sub_topic.name}' from topic: '#{topic.name}'"
            )
            # send a slack notification to the trainer
            Delayed::Job.enqueue(
                SlackUserNotification.new(
                    @settings[:slack_sync_bot_api_token],
                    trainer_email,
                    {
                        pretext: 'Notification from Cloudwick Sync',
                        title: "Assignment Submission made by #{user.first_name} #{user.last_name}",
                        title_link: 'http://sync.cloudwick.com/training',
                        body: "#{user.first_name} #{user.last_name} has made an assignment (#{assignment.name}) submission of sub-topic: '#{sub_topic.name}' from topic: '#{topic.name}'. Please review the assignment submission by clicking the above link.",
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

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/assignment/:assignmentid/:consultantid/approve' do |trackid, topicid, subtopicid, assignmentid, consultantid|
        sub_topic = TrainingSubTopic.find(subtopicid)
        assignment = sub_topic.training_assignments.find(assignmentid)

        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        trainee = Consultant.find(consultantid)
        trainer = Consultant.find(@session_username)

        assignment.training_assignment_submissions.find_by(
            consultant_id: consultantid
        ).update_attributes(
            status: 'APPROVED'
        )

        Consultant.where(team: trainee.team).each do |consultant|
          TrainingNotification.create(
              originator: @session_username,
              name: "#{trainer.first_name} #{trainer.last_name}",
              broadcast: 'T',
              destination: trainee.id,
              team: trainee.team,
              type: 'ASSIGNMENT',
              sub_type: 'APPROVAL',
              track: trackid,
              topic: topicid,
              sub_topic: subtopicid,
              assignment_id: assignmentid,
              message: "Approved #{trainee.first_name} #{trainee.last_name}'s assignment('#{assignment.name}') submission from sub_topic: '#{sub_topic.name}'"
          )
        end
        Delayed::Job.enqueue(
            SlackUserNotification.new(
                @settings[:slack_sync_bot_api_token],
                trainee.email,
                {
                    pretext: 'Notification from Cloudwick Sync',
                    title: 'Assignment Submission Approved.',
                    title_link: 'http://sync.cloudwick.com/training',
                    body: "#{trainer.first_name} #{trainer.last_name} approved your '#{assignment.name}' submission from topic: '#{topic.name}'.",
                    color: 'success',
                    fields: [
                        { title: 'Approved by', value: "#{trainer.first_name} #{trainer.last_name}", short: true },
                        { title: 'Approved on', value: DateTime.now.strftime('%d/%m/%Y'), short: true }
                    ]
                }
            ),
            queue: 'slack_notifications',
            priority: 10,
            run_at: 1.seconds.from_now
        )

        flash[:info] = 'Successfully registered event, sent notification to trainee'
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/assignment/:assignmentid/:consultantid/redo' do |trackid, topicid, subtopicid, assignmentid, consultantid|
        success = true
        message = 'Successfully registered event, sent notification to trainee'

        reason = params[:reason]

        sub_topic = TrainingSubTopic.find(subtopicid)
        assignment = sub_topic.training_assignments.find(assignmentid)

        trainee = Consultant.find(consultantid)
        trainer = Consultant.find(@session_username)

        assignment.training_assignment_submissions.find_by(
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
            type: 'ASSIGNMENT',
            sub_type: 'APPROVAL',
            track: trackid,
            topic: topicid,
            sub_topic: subtopicid,
            assignment_id: assignmentid,
            message: "Please review your your assignment('#{assignment.name}') submission from sub_topic: '#{sub_topic.name}'"
        )

        Delayed::Job.enqueue(
            SlackUserNotification.new(
                @settings[:slack_sync_bot_api_token],
                trainee.email,
                #"'#{trainer.first_name} #{trainer.last_name}' has disapproved your assignment submission '#{assignment.name}' from topic: '#{topic.name}'. Notes from trainer: #{reason}. Please review the submission based on trainer notes/comments and re-submit it."
                {
                    pretext: 'Notification from Cloudwick Sync',
                    title: 'Assignment Submission disapproved.',
                    title_link: 'http://sync.cloudwick.com/training',
                    body: "#{trainer.first_name} #{trainer.last_name} disapproved your '#{assignment.name}' submission from topic: '#{topic.name}'. Please review the assignment submission based on the comments/notes provided by trainer and re-submit it.",
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