module Sync
  module Routes
    class Timesheets < Base
      %w(/timesheets /timesheets/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/timesheets' do
        protected!

        erb :timesheets, locals: {
            vendors: TimeVendor.all,
            currentweek: dates_week(Date.today) {|d| d}
        }
      end

      get '/timesheets/manage' do
        protected!

        erb :timesheets_manage, locals: {
          vendors: TimeVendor.all,
          clients: TimeClient.all
        }
      end

      get '/timesheets/pending' do
        protected!

        erb :timesheets_pending, locals: {
          pending_approvals: Timesheet.where(status: 'SUBMITTED')
        }
      end

      get '/timesheets/approved' do
        protected!

        erb :timesheets_approved, locals: {
          approved_timesheets: Timesheet.where(status: 'APPROVED')
        }
      end

      post '/timesheets/approvals/deny/:id' do |id|
        ts = Timesheet.find(id)
        ts.update_attributes(status: 'REJECTED', disapproved_by: @user.name, disapproved_at: DateTime.now)

        flash[:info] = 'Successfully disapproved the timesheet approval'
        redirect '/timesheets/pending'
      end

      post '/timesheets/approvals/approve/:id' do |id|
        ts = Timesheet.find(id)
        ts.update_attributes(status: 'APPROVED', approved_by: @user.name, approved_at: DateTime.now)

        flash[:info] = 'Successfully approved the timesheet approval'
        redirect '/timesheets/pending'
      end

      #
      # Consultant timesheet routes
      #

      get '/timesheets/:userid/:year/:weeknum' do |userid, year, weeknum|
        self_protected!(userid)

        # Get the last date in the week from week number of the year
        date = Date.commercial(year.to_i, weeknum.to_i)
        week_start = Date.commercial(year.to_i, weeknum.to_i, 1)
        week_end = Date.commercial(year.to_i, weeknum.to_i, 7)
        dates = dates_week(date) { |d| d }
        contains_none = true

        user_projects = TimeProject.all_in(team: [userid])

        user_projects.each do |project|
          date_range = project.start_date..project.end_date
          if date_range === week_start || date_range === week_end
            contains_none = false
            timesheet = Timesheet.find_or_create_by(project_code: project.project_code, consultant: userid, week: date)
            dates.each do |d|
              timesheet.timesheet_details.find_or_create_by(workday: d)
            end
            project.timesheets << timesheet
          end
        end

        erb :consultant_timesheets, locals: {
            userid: userid,
            projects: user_projects,
            weekdates: dates,
            year: year,
            weeknum: weeknum,
            date: date,
            week_start: week_start,
            week_end: week_end,
            contains_none: contains_none
        }
      end

      post '/timesheets/save/:projectid/:userid/:year/:weeknum' do |projectid, userid, year, weeknum|
        success = true
        message = 'Successfully saved timesheet'

        current_week = Date.commercial(year.to_i, weeknum.to_i)

        timesheet = Timesheet.find_by(
            project_code: projectid,
            consultant: userid,
            week: current_week
        )

        dates = params.select { |_k, _| _k.to_s.match(/\d{4}-\d{2}-\d{2}/) }

        dates.each do |_, _v|
          unless _v =~ /^(2[0-3]|[01]?[0-9])\.([0-5]?[0-9])$|^(2[0-3]|[01]?[0-9])$/
            success = false
            message = 'Hours not properly formatted, should in the format HH.MM or HH and cannot exceed 24 hours'
          end
        end

        if success
          dates.each do |_k, _v|
            timesheet_details = timesheet.timesheet_details.find_by(
                workday: Date.strptime(_k, '%Y-%m-%d')
            )
            timesheet_details.update_attributes!(hours: _v.to_f, logged_at: DateTime.now)
          end

          total_hours = dates.values.map { |h| h.to_f }.inject{ |sum,x| sum + x }

          timesheet.update_attributes(total_hours: total_hours, status: 'SAVED', saved_at: DateTime.now)

          TimeProject.find(projectid).timesheets << timesheet
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/submit/:projectid/:userid/:year/:weeknum' do |projectid, userid, year, weeknum|
        success = true
        message = 'Successfully marked timesheet as submitted'

        Timesheet.find_by(
            project_code: projectid,
            consultant: userid,
            week: Date.commercial(year.to_i, weeknum.to_i)
        ).update_attributes(status: 'SUBMITTED', submitted_at: DateTime.now)

        { success: success, msg: message }.to_json
      end

      # upload an attachment for a timesheet specific to particular week
      post '/upload/timesheet/:projectid/:email/:year/:week' do |project_id, email, year, week|
        timesheet = Timesheet.find_by(
            project_code: project_id,
            consultant: email,
            week: Date.commercial(year.to_i, week.to_i)
        )
        s_files = []
        w_files = []

        params[:timesheets].each do |attachment|
          # filename is in format: consultantname_projectid_year_week_filename
          file_name = email.split('@').first.upcase + '_' + project_id + '_' + year + '_' + week + '_' + attachment[:filename]
          temp_file = attachment[:tempfile]
          attachment_id = upload_file(temp_file,file_name)
          if attachment_id
            timesheet.timesheet_attachments.find_or_create_by(file_name: file_name) do |att|
              att.id = attachment_id
              att.filename = file_name
              att.uploaded_date = DateTime.now
            end
            s_files << file_name
          else
            w_files << file_name
          end
        end
        flash[:info] = "Successfully uploaded files '#{s_files.join(',')}'" unless s_files.empty?
        flash[:warning] = "Failed uploading attachment. AAttachment(s) with name '#{w_files.join(',')}' already exists!." unless w_files.empty?
        redirect back
      end
    end
  end
end