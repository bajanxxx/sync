module Sync
  module Routes
    class TimesheetProjects < Base
      get '/timesheets/projects' do
        protected!

        erb :timesheets_projects, locals: {
          projects: TimeProject.all,
          vendors: TimeVendor.all,
          clients: TimeClient.all,
          consultants: Consultant.all
        }
      end

      get '/timesheets/projects/:project_id' do |project_id|
        protected!

        prj = TimeProject.find(project_id)
        team_members = prj.team.map do |_m|
          _consultant = Consultant.find(_m)
          "#{_consultant.first_name} #{_consultant.last_name}"
        end

        erb :timesheets_project, locals: {
          p: prj,
          team_members: team_members,
          consultants: Consultant.asc(:email)
        }
      end

      post '/timesheets/project/add' do
        client_id = params[:ClientName]
        vendor_id = params[:VendorName]
        project_name = params[:ProjectName]
        project_code = params[:ProjectCode]
        project_type = params[:ProjectType]
        start_date = params[:StartDate]
        end_date = params[:EndDate]
        notes = params[:Notes]
        sales = params[:Sales]
        team = params[:Team]
        billable = params[:Billable]
        invoice_method = params[:InvoiceMethod]
        project_flat_rate = params[:ProjectFlatRate]
        monthly_flat_rate = params[:MonthlyFlatRate]

        success    = true
        message    = 'Successfully added project'

        unless team
          success = false
          message = "Param 'team' cannot be empty, select at least one consultant"
        end

        %w(ProjectName ProjectCode StartDate EndDate Notes Team).each do |param|
          if params[param.to_sym].nil? || params[param.to_sym].empty?
            success = false
            message = "Param '#{param}' cannot be empty"
          end
        end

        unless project_code =~ /[a-zA-Z_\-\.]/
          success = false
          message = "Project code can only contain 'A-Z', 'a-z', '.', '-', '_' characters"
        end

        if Date.strptime(start_date, '%m/%d/%Y') > Date.strptime(end_date, '%m/%d/%Y')
          success = false
          message = 'Start date should be less than end date'
        end

        _time_project = TimeProject.find(project_code)
        if _time_project
          success = false
          message = "Project with code #{project_code} already exists and is not unique"
        end

        if sales
          unless sales =~ /^\S+@cloudwick.com$/
            success = false
            message = 'Sales associate email address is not properly formatted'
          end
        else
          sales = ''
        end

        if billable == 'on'
          if invoice_method == 'project_flat_rate'
            unless project_flat_rate =~ /^\d+\.\d[0-2]$/
              success = false
              message = 'Price is not properly formatted, should be of format 00.00'
            end
          elsif invoice_method == 'monthly_flat_rate'
            unless monthly_flat_rate =~ /^\d+\.\d[0-2]$/
              success = false
              message = 'Price is not properly formatted, should be of format 00.00'
            end
          end
        end

        if success
          begin
            if billable == 'on'
              if invoice_method == 'person_hourly_rate'
                project = TimeProject.create(
                  project_code: project_code,
                  name: project_name,
                  type: project_type,
                  start_date: Date.strptime(start_date, '%m/%d/%Y'),
                  end_date: Date.strptime(end_date, '%m/%d/%Y'),
                  notes: notes,
                  sales: sales,
                  team: team,
                  billable?: true,
                  invoice_method: :person_hourly_rate,
                  vendor_id: vendor_id,
                  client_id: client_id
                )
                team.each do |tm|
                  project.time_project_team_members << TimeProjectTeamMember.new(
                    consultant: tm,
                    price: params["#{tm.split('@').first.gsub('.', '')}Price".to_sym]
                  )
                end
              elsif invoice_method == 'project_flat_rate'
                project = TimeProject.create(
                  project_code: project_code,
                  name: project_name,
                  type: project_type,
                  start_date: Date.strptime(start_date, '%m/%d/%Y'),
                  end_date: Date.strptime(end_date, '%m/%d/%Y'),
                  notes: notes,
                  sales: sales,
                  team: team,
                  billable?: true,
                  invoice_method: :project_flat_rate,
                  vendor_id: vendor_id,
                  client_id: client_id,
                  project_flat_rate: params[:ProjectFlatRate]
                )
              elsif invoice_method == 'monthly_flat_rate'
                project = TimeProject.create(
                  project_code: project_code,
                  name: project_name,
                  type: project_type,
                  start_date: Date.strptime(start_date, '%m/%d/%Y'),
                  end_date: Date.strptime(end_date, '%m/%d/%Y'),
                  notes: notes,
                  sales: sales,
                  team: team,
                  billable?: true,
                  invoice_method: :project_flat_rate,
                  vendor_id: vendor_id,
                  client_id: client_id,
                  project_monthly_flat_rate: params[:MonthlyFlatRate]
                )
              end
            else
              project = TimeProject.create(
                project_code: project_code,
                name: project_name,
                type: project_type,
                start_date: Date.strptime(start_date, '%m/%d/%Y'),
                end_date: Date.strptime(end_date, '%m/%d/%Y'),
                notes: notes,
                sales: sales,
                team: team,
                vendor_id: vendor_id,
                client_id: client_id
              )
            end

          rescue ArgumentError
            success = false
            message = 'Cannot parse date format (expected format: mm/dd/yyyy)'
          end

          flash[:info] = message
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/projects/update' do
        project_id = params[:pk]
        update_key    = params[:name]
        update_value  = params[:value]
        status_code = 200
        message       = "Successfully updated #{update_key} to #{update_value}"

        project = TimeProject.find(project_id)

        begin
          case update_key
            when 'start_date', 'end_date'
              project.update_attribute(update_key.to_sym, Date.strptime(update_value, '%Y-%m-%d'))
            when 'billable?', 'invoice_method'
              project.update_attribute(update_key.to_sym, update_value.first)
            when /.*@cloudwick.com/
              project.time_project_team_members.find_by(consultant: update_key).update_attribute(:price, update_value)
            when 'team'
              existing_members = project.time_project_team_members.map(&:consultant)
              new_members = update_value
              to_add = new_members - existing_members
              to_remove = existing_members - new_members
              # add new members
              to_add.each do |consultant|
                project.time_project_team_members << TimeProjectTeamMember.new(
                  consultant: consultant,
                  price: '00.00'
                )
              end
              # remove not required members
              to_remove.each do |consultant|
                project.time_project_team_members.find_by(consultant: consultant).remove
              end
              # also update the team array
              project.update_attribute(update_key.to_sym, update_value)
            when 'project_flat_rate', 'project_monthly_flat_rate'
              unless update_value =~ /^\d+\.\d[0-2]$/
                status_code = 500
                message = 'Price not properly formatted'
                return [status_code, message]
              end
              project.update_attribute(update_key.to_sym, update_value)
            else
              project.update_attribute(update_key.to_sym, update_value)
          end
        rescue
          status_code = 500
          message = "Failed to update(#{update_key})"
        end
        # Return status and response text
        [status_code, message]
      end

      post '/timesheets/project/update/:id' do |id|
        success    = true
        message    = 'Successfully added project'

        project_name = params["ProjectName-#{id}"]
        start_date = params["StartDate-#{id}"]
        end_date = params["EndDate-#{id}"]
        notes = params["Notes-#{id}"]
        team = params["Team-#{id}"]

        unless team
          success = false
          message = "Param 'team' cannot be empty, select at least one consultant"
        end

        if Date.strptime(start_date, '%m/%d/%Y') > Date.strptime(end_date, '%m/%d/%Y')
          success = false
          message = 'start date should be less than end date'
        end

        begin
          if success
            project = TimeProject.find(id)
            project.update_attributes(
              name: project_name,
              start_date: Date.strptime(start_date, '%m/%d/%Y'),
              end_date: Date.strptime(end_date, '%m/%d/%Y'),
              notes: notes,
              team: team
            )
          end
        rescue ArgumentError
          success = false
          message = 'Cannot parse date format (expected format: mm/dd/yyyy)'
        end

        flash[:info] = message

        { success: success, msg: message }.to_json
      end

      # upload an attachment for a timesheet specific to particular week
      post '/upload/timesheets/project/:projectid' do |project_id|
        project = TimeProject.find(project_id)
        s_files = []
        w_files = []

        params[:files].each do |attachment|
          file_name = project_id + '_' + attachment[:filename]
          temp_file = attachment[:tempfile]
          attachment_id = upload_file(temp_file,file_name)
          if attachment_id
            project.time_project_attachments.find_or_create_by(file_name: file_name) do |att|
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
        flash[:warning] = "Failed uploading attachment. Attachment(s) with name '#{w_files.join(',')}' already exists!." unless w_files.empty?
        redirect back
      end
    end
  end
end