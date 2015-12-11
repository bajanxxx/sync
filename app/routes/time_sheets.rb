module Sync
  module Routes
    class TimeSheets < Base
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

      get '/timesheets/projects' do
        protected!

        erb :timesheets_projects, locals: {
            projects: TimeProject.all,
            vendors: TimeVendor.all,
            clients: TimeClient.all,
            consultants: Consultant.all
        }
      end

      get '/timesheets/reports/:year/:month' do |year, month|
        protected!

        data = {}
        _debug = {}
        start_date = Date.new(year.to_i, month.to_i - 1, -5)
        end_date = Date.new(year.to_i, month.to_i, -1)

        Consultant.all.each do |_consultant|
          _total = 0.0
          _debug[_consultant.email.to_sym] = []

          Timesheet.where(consultant: _consultant.email, week: start_date..end_date).each do |entry|
            entry.timesheet_details.each do |td|
              if td.workday >= Date.new(year.to_i, month.to_i) && td.workday <= Date.new(year.to_i, month.to_i, -1)
                _debug[_consultant.email.to_sym] << { day: td.workday, hours: td.hours }
                _total += td.hours
              end
            end
          end

          data[_consultant.email.to_sym] = _total
        end

        erb :timesheets_reports, locals: {
            data: data,
            year: year,
            month: month
        }
      end

      get '/timesheets/manage' do
        protected!

        erb :timesheets_manage, locals: {
            vendors: TimeVendor.all,
            clients: TimeClient.all
        }
      end

      post '/timesheets/manage/vendor' do
        success    = true
        message    = "Successfully created vendor"

        name = params[:VendorName]
        address = params[:Address]
        preferred_currency = params[:PreferredCurrency]

        if name.empty? || address.empty? || preferred_currency.empty?
          success = false
          message = "fields cannot be empty"
        else
          TimeVendor.create(name: name, address: address, preferred_currency: preferred_currency)
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/manage/vendor/:vid/update' do |vid|
        success = true
        message = "Successfully updated vendor details"

        name = params[:name]
        address = params[:address]
        currency = params[:currency]

        if name.empty? || address.empty? || currency.empty?
          success = false
          message = "fields cannot be empty"
        else
          TimeVendor.find(vid).update_attributes(
              name: name,
              address: address,
              preferred_currency: currency
          )
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/manage/client' do
        success    = true
        message    = 'Successfully created vendor'

        name = params[:ClientName]
        address = params[:ClientAddress]
        preferred_currency = params[:PreferredClientCurrency]

        if name.empty? || address.empty? || preferred_currency.empty?
          success = false
          message = 'fields cannot be empty'
        else
          TimeClient.create(name: name, address: address, preferred_currency: preferred_currency)
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/manage/client/:cid/update' do |cid|
        success = true
        message = 'Successfully updated client details'

        name = params[:name]
        address = params[:address]
        currency = params[:currency]

        if name.empty? || address.empty? || currency.empty?
          success = false
          message = 'fields cannot be empty'
        else
          TimeClient.find(cid).update_attributes(
              name: name,
              address: address,
              preferred_currency: currency
          )
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/project/add' do
        client_id = params[:ClientName]
        vendor_id = params[:VendorName]
        project_name = params[:ProjectName]
        project_code = params[:ProjectCode]
        start_date = params[:StartDate]
        end_date = params[:EndDate]
        notes = params[:Notes]
        team = params[:Team]

        success    = true
        message    = 'Successfully added project'

        unless team
          success = false
          message = "Param 'team' cannot be empty, select atleast one consultant"

          return { success: success, msg: message }.to_json unless success
        end

        %w(ProjectName ProjectCode StartDate EndDate Notes Team).each do |param|
          if params[param.to_sym].empty?
            success = false
            message = "Param '#{param}' cannot be empty"
          end
          return { success: success, msg: message }.to_json unless success
        end

        if Date.strptime(start_date, "%m/%d/%Y") > Date.strptime(end_date, "%m/%d/%Y")
          success = false
          message = "start date should be less than end date"

          return { success: success, msg: message }.to_json unless success
        end

        _time_project = TimeProject.find(project_code)
        if _time_project
          success = false
          message = "Project with code #{project_code} already exists and is not unique"
          return { success: success, msg: message }.to_json unless success
        end

        begin
          client = TimeClient.find(client_id)
          vendor = TimeVendor.find(vendor_id)

          if success
            project = TimeProject.create(
                project_code: project_code,
                name: project_name,
                start_date: Date.strptime(start_date, "%m/%d/%Y"),
                end_date: Date.strptime(end_date, "%m/%d/%Y"),
                notes: notes,
                team: team
            )

            project.time_client = client
            project.time_vendor = vendor
          end
        rescue ArgumentError
          success = false
          message = "Cannot parse date format (expected format: mm/dd/yyyy)"
        end

        flash[:info] = message
        { success: success, msg: message }.to_json
      end

      post '/timesheets/project/update/:id' do |id|
        success    = true
        message    = 'Successfully added project'

        client_id = params["ClientName-#{id}"]
        vendor_id = params["VendorName-#{id}"]
        project_name = params["ProjectName-#{id}"]
        project_code = params["ProjectCode-#{id}"]
        start_date = params["StartDate-#{id}"]
        end_date = params["EndDate-#{id}"]
        notes = params["Notes-#{id}"]
        team = params["Team-#{id}"]

        unless team
          success = false
          message = "Param 'team' cannot be empty, select atleast one consultant"

          return { success: success, msg: message }.to_json unless success
        end

        if Date.strptime(start_date, "%m/%d/%Y") > Date.strptime(end_date, "%m/%d/%Y")
          success = false
          message = "start date should be less than end date"

          return { success: success, msg: message }.to_json unless success
        end

        begin
          if success
            project = TimeProject.find(id)
            project.update_attributes(
                name: project_name,
                start_date: Date.strptime(start_date, "%m/%d/%Y"),
                end_date: Date.strptime(end_date, "%m/%d/%Y"),
                notes: notes,
                team: team
            )
          end
        rescue ArgumentError
          success = false
          message = "Cannot parse date format (expected format: mm/dd/yyyy)"
        end

        flash[:info] = message

        { success: success, msg: message }.to_json
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

        flash[:info] = 'Sucessfully disapproved the timesheet approval'
        redirect "/timesheets/pending"
      end

      post '/timesheets/approvals/approve/:id' do |id|
        ts = Timesheet.find(id)
        ts.update_attributes(status: 'APPROVED', approved_by: @user.name, approved_at: DateTime.now)

        flash[:info] = 'Sucessfully approved the timesheet approval'
        redirect "/timesheets/pending"
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
            dates.each do |date|
              timesheet.timesheet_details.find_or_create_by(workday: date)
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
        message = 'Successfully added'

        current_week = Date.commercial(year.to_i, weeknum.to_i)

        timesheet = Timesheet.find_by(
            project_code: projectid,
            consultant: userid,
            week: current_week
        )

        dates = params.select { |_k, _v| _k.to_s.match(/\d{4}-\d{2}-\d{2}/) }

        dates.each do |_k, _v|
          timesheet_details = timesheet.timesheet_details.find_by(
              workday: Date.strptime(_k, "%Y-%m-%d")
          )
          timesheet_details.update_attributes!(hours: _v)
        end

        total_hours = dates.values.map { |h| h.to_f }.inject{ |sum,x| sum + x }

        timesheet.update_attributes(total_hours: total_hours, status: "SAVED")

        TimeProject.find(projectid).timesheets << timesheet

        { success: success, msg: message }.to_json
      end

      post '/timesheets/submit/:projectid/:userid/:year/:weeknum' do |projectid, userid, year, weeknum|
        success = true
        message = 'Successfully added'

        Timesheet.find_by(
            project_code: projectid,
            consultant: userid,
            week: Date.commercial(year.to_i, weeknum.to_i)
        ).update_attributes(status: 'SUBMITTED')

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

        params[:timesheets].each do |attachement|
          # filename is in format: consultantname_projectid_year_week_filename
          file_name = email.split('@').first.upcase + '_' + project_id + '_' + year + '_' + week + '_' + attachement[:filename]
          temp_file = attachement[:tempfile]
          attachement_id = upload_file(temp_file,file_name)
          if attachement_id
            timesheet.timesheet_attachments.find_or_create_by(file_name: file_name) do |att|
              att.id = attachement_id
              att.filename = file_name
              att.uploaded_date = DateTime.now
            end
            s_files << file_name
          else
            w_files << file_name
          end
        end
        flash[:info] = "Successfully uploaded files '#{s_files.join(',')}'" unless s_files.empty?
        flash[:warning] = "Failed uploading attachement. Attachement(s) with name '#{w_files.join(',')}' already exists!." unless w_files.empty?
        redirect back
      end
    end
  end
end