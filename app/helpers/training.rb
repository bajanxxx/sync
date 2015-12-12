module Sync
  module Helpers
    module Training
      def get_user_fullname(userid)
        User.find(userid).name
      end

      def get_track_name(track_id)
        TrainingTrack.find(track_id).name
      end

      def get_topic_name(topic_id)
        TrainingTopic.find(topic_id).name
      end

      # Calculate topic progress which is aggregate from all subtopics and project's for this topic.
      # 70% of weightage is for subtopics and 30% is for projects
      def topic_progress(consultant, topic)
        projects_progress = topic_projects_progress(consultant, topic)
        projects_progress_weighted = projects_progress * 0.30

        sub_topics_progress = []
        topic.training_sub_topics.each do |subtopic|
          sub_topics_progress << sub_topic_progress(consultant, subtopic)
        end

        aggregate_sub_topics_progress = if sub_topics_progress.empty?
                                          1.0 # No sub topics are present, hence cannot conclude progress
                                        else
                                          ( sub_topics_progress.inject(:+) / sub_topics_progress.count ).to_f
                                        end
        sub_topics_progress_weighted = aggregate_sub_topics_progress * 0.70

        projects_progress_weighted + sub_topics_progress_weighted
      end

      # Calculate projects progress for a specified topic
      def topic_projects_progress(consultant, topic)
        total_projects = topic.training_projects.count
        topic_projects_progress = []
        if total_projects != 0 # only consider progress if there are projects associated with a topic
          project_submissions = 0
          project_approvals = 0

          topic.training_projects.each do |_p|
            # TODO handle other status values
            project_submissions += _p.training_project_submissions.where(consultant_id: consultant.email, status: 'SUBMITTED').count
            project_approvals += _p.training_project_submissions.where(consultant_id: consultant.email, status: 'APPROVED').count
          end

          topic_projects_progress << (((project_submissions * 1.0) + project_approvals * 2.0) / (total_projects * 2.0)).to_f
        end

        if topic_projects_progress.empty?
          1.0 # no projects are associated with this topic
        else
          ( topic_projects_progress.inject(:+) / topic_projects_progress.count )
        end
      end

      # Calculate subtopic progress this is calculated from assignments progress, 50% of weightage
      # is for assignments submissions and 50% is for approvals
      def sub_topic_progress(consultant, subtopic)
        # total assignments in this subtopic
        total_assignments = subtopic.training_assignments.count
        subtopic_assignments_progress = []
        if total_assignments != 0 # only consider progress if there are assignments associated with this sub-topic
          assignment_submissions = 0
          assignment_approvals = 0
          subtopic.training_assignments.each do |_a|
            # TODO: handle other status values
            assignment_submissions += _a.training_assignment_submissions.where(consultant_id: consultant.email, status: 'SUBMITTED').count
            assignment_approvals += _a.training_assignment_submissions.where(consultant_id: consultant.email, status: 'APPROVED').count
          end

          subtopic_assignments_progress << (((assignment_submissions * 1.0) + assignment_approvals * 2.0) / (total_assignments * 2.0)).to_f
        end

        if subtopic_assignments_progress.empty?
          1.0 # no assignments are associated with this sub_topic hence 100% progress
        else
          ( subtopic_assignments_progress.inject(:+) / subtopic_assignments_progress.count )
        end
      end

      # access: {preq: true, core: false, adv: false, opt: false}
      def user_track_access_breakdown(consultant, track)
        access = { preq: true, core: false, adv: false, opt: false, certs: false }
        topics = track.training_topics
        topics_by_category = topics.group_by { |t| t[:category] }

        preqs_progress = topics_by_category['P'].map { |t| topic_progress(consultant, t) }.instance_eval { reduce(:+) / size.to_f }
        if preqs_progress > 0.8
          access[:core] = true
        end

        if access[:core]
          cores_progress = topics_by_category['C'].map { |t| topic_progress(consultant, t) }.instance_eval { reduce(:+) / size.to_f }
          if ((preqs_progress + cores_progress) / 2.to_f) > 0.8
            access[:adv] = true
          end
        end

        if access[:adv]
          advs_progress = topics_by_category['A'].map { |t| topic_progress(consultant, t) }.instance_eval { reduce(:+) / size.to_f }
          if ((preqs_progress + cores_progress + advs_progress) / 3.to_f) > 0.8
            access[:opt] = true
          end
        end

        if access[:opt]
          opts_progress = topics_by_category['O'].map { |t| topic_progress(consultant, t) }.instance_eval { reduce(:+) / size.to_f }
          if (( preqs_progress + cores_progress + advs_progress + opts_progress ) / 4.to_f) > 0.7
            access[:certs] = true
          end
        end

        access
      end

      # does the user has access to this topic or not
      # return true or false
      def user_access_to_topic(consultant, track, topic)
        topic_category = topic.category
        access = user_track_access_breakdown(consultant, track)
        case topic_category
          when 'P'
            access[:preq]
          when 'C'
            access[:core]
          when 'A'
            access[:adv]
          when 'O'
            access[:opt]
        end
      end

      def user_access_to_subtopic(consultant, track, topic, subtopic)
        user_access_to_topic(consultant, track, topic)
      end

      # Builds out training progress for a given consultant in the following format
      # {:DO=>{:progress=>[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], :topics=>[:LX, :SCP, :BD101, :HDOPS, :CDOPS, :AUTO, :AWS, :SCR, :BD501, :VCS, :JIRA, :CI], :LX=>{:progress=>0.0}, :SCP=>{:progress=>0.0}, :BD101=>{:progress=>0.0}, :HDOPS=>{:progress=>0.0}, :CDOPS=>{:progress=>0.0}, :AUTO=>{:progress=>0.0}, :AWS=>{:progress=>0.0}, :SCR=>{:progress=>0.0}, :BD501=>{:progress=>0.0}, :VCS=>{:progress=>0.0}, :JIRA=>{:progress=>0.0}, :CI=>{:progress=>0.0}, :overall=>0.0}}
      def build_training_progess(consultant)
        progress = Hash.new { |hash, key| hash[key] = {} }

        unless consultant.details.training_tracks.empty?
          consultant.details.training_tracks.each do |_tcode|
            _track = TrainingTrack.find_by(code: _tcode)

            # for each track find progress
            progress[_track.code.to_sym] = Hash.new { |hash, key| hash[key] = {} }
            progress[_track.code.to_sym][:progress] = []
            progress[_track.code.to_sym][:topics] = []

            _track.training_topics.each do |_topic|
              progress[_track.code.to_sym][:topics] << _topic.code.to_sym
              progress[_track.code.to_sym][_topic.code.to_sym][:progress] = topic_progress(consultant, _topic)

              progress[_track.code.to_sym][:progress] << progress[_track.code.to_sym][_topic.code.to_sym][:progress]
            end # topics
            progress[_track.code.to_sym][:overall] = if !progress[_track.code.to_sym][:progress].empty?
                                                       progress[_track.code.to_sym][:progress].inject(:+) / progress[_track.code.to_sym][:progress].count
                                                     else
                                                       0.0
                                                     end
          end
        end

        progress
      end

      # Give back project submissions made for a given team and topic
      # {
      #     "Project #1" => {
      #                             :heading => "LAMP",
      #         "mouna.mekala@cloudwick.com" => {
      #           :consultantname => "Mouna Mekala",
      #                     :date => Wed, 11 Nov 2015 14:41:41 -0800,
      #                     :link => "https://github.com/cloudwicklabs/generator",
      #             :resubmission => false
      #         }
      #     }
      # }
      def project_submissions_for_topic(topic, teamid)
        project_submissions = Hash.new { |hash, key| hash[key] = {} }
        consultants = Consultant.where(team: teamid)
        topic.training_projects.each do |_project|
          project_submissions[_project.id][:heading] = _project.heading
          project_submissions[_project.id][:name] = _project.name
          submissions = _project.training_project_submissions.where(:consultant_id.in => consultants.map(&:id), status: 'SUBMITTED').order_by(:created_at => 'desc')
          submissions.each do |_submission|
            consultant = Consultant.find(_submission.consultant_id)
            project_submissions[_project.id][consultant.id] = { consultantname: "#{consultant.first_name} #{consultant.last_name}" , date: _submission.created_at, link: _submission.submission_link, resubmission: _submission.resubmission, submissionid: _submission.id }
          end
        end
        project_submissions
      end

      # Give back assignment submissions for a given team and sub_topic
      # {
      #     "Assignment #1" => {
      #                             :heading => "First Assignment",
      #         "mouna.mekala@cloudwick.com" => {
      #                     :date => Wed, 11 Nov 2015 14:41:40 -0800,
      #                     :link => "https://github.com/cloudwicklabs/generator",
      #             :resubmission => false
      #         }
      #     }
      # }
      def assignment_submissions_for_sub_topic(sub_topic, teamid)
        assignment_submissions = Hash.new { |hash, key| hash[key] = {} }
        consultants = Consultant.where(team: teamid)
        sub_topic.training_assignments.each do |_assignment|
          assignment_submissions[_assignment.id][:name] = _assignment.name
          assignment_submissions[_assignment.id][:heading] = _assignment.heading
          submissions = _assignment.training_assignment_submissions.where(:consultant_id.in => consultants.map(&:id), status: 'SUBMITTED').order_by(:created_at => 'desc')
          submissions.each do |_submission|
            consultant = Consultant.find(_submission.consultant_id)
            assignment_submissions[_assignment.id][consultant.id] = { name: "#{consultant.first_name} #{consultant.last_name}" , date: _submission.created_at, link: _submission.submission_link, resubmission: _submission.resubmission, submissionid: _submission.id }
          end
        end
        assignment_submissions
      end
    end
  end
end