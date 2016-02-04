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
        projects_weightage = 0.30
        sub_topics_weightage = 0.70

        total_projects = topic.training_projects.count
        total_assignments = if topic.training_sub_topics.count == 0
                              0
                            else
                              topic.training_sub_topics.map { |st| st.training_assignments.count }.instance_eval { reduce(:+) }
                            end

        if total_projects == 0 # if there are no projects then the total weightage is calculated towards sub_topics and their assignments
          sub_topics_weightage = 1.0
        elsif total_assignments == 0 # similarly if there are no assignments if any of the subtopics, then the total weightage is calculated towards projects
          projects_weightage = 1.0
        end

        projects_progress = topic_projects_progress(consultant, topic)
        projects_progress_weighted = projects_progress * projects_weightage

        sub_topics_progress = sub_topics_progress(consultant, topic)
        sub_topics_progress_weighted = sub_topics_progress * sub_topics_weightage

        if total_projects == 0.0 && total_assignments == 0.0
          -1
        else
          projects_progress_weighted + sub_topics_progress_weighted
        end
      end

      # Calculate projects progress for a specified topic
      def topic_projects_progress(consultant, topic)
        total_projects = topic.training_projects.count

        if total_projects != 0
          project_submissions = topic.training_projects.map { |p| p.training_project_submissions.where(consultant_id: consultant.id, status: "SUBMITTED").count }.instance_eval { reduce(:+) }
          project_approvals = topic.training_projects.map { |p| p.training_project_submissions.where(consultant_id: consultant.id, status: "APPROVED").count }.instance_eval { reduce(:+) }

          (((project_submissions * 1.0) + project_approvals * 2.0) / (total_projects * 2.0)).to_f
        else
          0.0
        end
      end

      # Calculate subtopic progress this is calculated from assignments progress, 50% of weightage
      # is for assignments submissions and 50% is for approvals
      def sub_topics_progress(consultant, topic)
        # total assignments in this subtopic

        total_assignments = if topic.training_sub_topics.count == 0
                              0
                            else
                              topic.training_sub_topics.map { |st| st.training_assignments.count }.instance_eval { reduce(:+) }
                            end
        if total_assignments != 0
          assignment_submissions = topic.training_sub_topics.map { |st|
            st.training_assignments.map { |a|
              a.training_assignment_submissions.where(consultant_id: consultant.id, status: "SUBMITTED").count
            }.instance_eval { reduce(:+) }
          }.compact.instance_eval { reduce(:+) }
          assignment_approvals = topic.training_sub_topics.map { |st|
            st.training_assignments.map { |a|
              a.training_assignment_submissions.where(consultant_id: consultant.id, status: "APPROVED").count
            }.instance_eval { reduce(:+) }
          }.compact.instance_eval { reduce(:+) }

          (((assignment_submissions * 1.0) + assignment_approvals * 2.0) / (total_assignments * 2.0)).to_f
        else
          0.0
        end
      end

      # access: {preq: true, core: false, adv: false, opt: false}
      def user_track_access_breakdown(consultant, track)
        access = { preq: true, core: false, adv: false, opt: false, certs: false }
        topics = track.training_topics
        topics_by_category = topics.group_by { |t| t[:category] }

        preqs_progress = category_progress(topics_by_category['P'], consultant)
        if preqs_progress > 0.6
          access[:core] = true
        end

        if access[:core]
          cores_progress = category_progress(topics_by_category['C'], consultant)
          if ((preqs_progress + cores_progress) / 2.to_f) > 0.7
            access[:adv] = true
          end
        end

        if access[:adv]
          advs_progress = category_progress(topics_by_category['A'], consultant)
          if ((preqs_progress + cores_progress + advs_progress) / 3.to_f) > 0.8
            access[:opt] = true
          end
        end

        if access[:opt]
          opts_progress = category_progress(topics_by_category['O'], consultant)
          if (( preqs_progress + cores_progress + advs_progress + opts_progress ) / 4.to_f) > 0.7
            access[:certs] = true
          end
        end

        access
      end

      def user_category_progress(consultant, track)
        progress = { preq: 0.0, core: 0.0, adv: 0.0, opt: 0.0, certs: 0.0}
        topics = track.training_topics
        topics_by_category = topics.group_by { |t| t[:category] }

        preqs_progress = category_progress(topics_by_category['P'], consultant)
        progress[:core] = preqs_progress


        cores_progress = category_progress(topics_by_category['C'], consultant)
        progress[:adv] = (preqs_progress + cores_progress) / 2.to_f


        advs_progress = category_progress(topics_by_category['A'], consultant)
        progress[:opt] = (preqs_progress + cores_progress + advs_progress) / 3.to_f


        opts_progress = category_progress(topics_by_category['O'], consultant)
        progress[:certs] = ( preqs_progress + cores_progress + advs_progress + opts_progress ) / 4.to_f

        progress
      end

      def category_progress(topics_by_category, consultant)
        progress = topics_by_category.map { |t| topic_progress(consultant, t) }.reject { |e| e == -1 }
        if progress.empty? # if there are topics with no projects and assignments in them
          0.0
        else
          progress.instance_eval { reduce(:+) / size.to_f }
        end
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

      def user_access_to_certification(consultant, track)
        access = user_track_access_breakdown(consultant, track)
        access[:certs]
      end

      # Builds out training progress for a given consultant in the following format
      # {:DO=>{:progress=>[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], :topics=>[:LX, :SCP, :BD101, :HDOPS, :CDOPS, :AUTO, :AWS, :SCR, :BD501, :VCS, :JIRA, :CI], :LX=>{:progress=>0.0}, :SCP=>{:progress=>0.0}, :BD101=>{:progress=>0.0}, :HDOPS=>{:progress=>0.0}, :CDOPS=>{:progress=>0.0}, :AUTO=>{:progress=>0.0}, :AWS=>{:progress=>0.0}, :SCR=>{:progress=>0.0}, :BD501=>{:progress=>0.0}, :VCS=>{:progress=>0.0}, :JIRA=>{:progress=>0.0}, :CI=>{:progress=>0.0}, :overall=>0.0}}
      def build_training_progress(consultant)
        progress = Hash.new { |hash, key| hash[key] = {} }

        # To get around not logged in users
        if consultant.details.nil?
          Detail.find_or_create_by(consultant_id: consultant.id)
        end

        unless consultant.details.training_tracks.empty?
          consultant.details.training_tracks.each do |_tcode|
            _track = TrainingTrack.find_by(code: _tcode)

            # for each track find progress
            progress[_track.code.to_sym] = Hash.new { |hash, key| hash[key] = {} }
            progress[_track.code.to_sym][:progress] = []
            progress[_track.code.to_sym][:topics] = []

            _track.training_topics.each do |_topic|
              progress[_track.code.to_sym][:topics] << _topic.code.to_sym
              topic_progress = topic_progress(consultant, _topic)
              progress[_track.code.to_sym][_topic.code.to_sym][:progress] = if topic_progress == -1
                                                                              0.0
                                                                            else
                                                                              topic_progress
                                                                            end

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