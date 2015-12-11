module Sync
  module Routes
    class ConsultantProjects < Base
      get '/consultant/:id/projects' do |id|
        self_protected!(id)

        erb :consultant_projects, locals: {
          consultant: Consultant.find(id),
          details: Detail.find_by(consultant_id: id)
        }
      end

      get '/consultant/:id/projects/add' do |id|
        erb :consultant_add_project, locals: { consultant: Consultant.find(id) }
      end

      post '/consultant/:id/projects/add' do |id|
        content_type :text
        success = true
        message = 'Successfully added project'

        project_name = params[:name]

        consultant = Consultant.find_by(email: id)
        details = Detail.find_by(consultant_id: id)
        _projects = details.projects.find_by(name: project_name)
        if _projects
          # project with same name exists
          success = false
          message = "Failed to add project as the project_name: #{project_name} already exists"
        else
          # project with the same name does not exist
          details.projects << Project.new(
            name: project_name,
            client: params[:client],
            title: params[:jobtitle],
            software: params[:softwareused].split(','),
            management_tools: params[:managementtoolsused].split(','),
            commercial_support: params[:commercialsupport].split(','),
            point_of_contact: params[:pointofcontact].split(',') || []
          )
          details.save

          # upload illustration if any
          if params[:illustrations]
            params[:illustrations].each do |illustration|
              file_name = "#{id}_#{project_name}_#{Time.now.getutc.to_i}_#{illustration[:filename]}"
              illustration_id = upload_file(illustration[:tempfile], file_name)
              if illustration_id
                details.projects.find_by(name: project_name).illustrations << Illustration.new(
                  file_id: illustration_id,
                  filename: file_name,
                  uploaded_date: DateTime.now
                )
              end
            end
          end
          # upload project documents if any
          if params[:documents]
            params[:documents].each do |document|
              file_name = "#{id}_#{project_name}_#{Time.now.getutc.to_i}_#{document[:filename]}"
              document_id = upload_file(document[:tempfile], file_name)
              if document_id
                details.projects.find_by(name: project_name).projectdocuments << ProjectDocument.new(
                  file_id: document_id,
                  filename: file_name,
                  uploaded_date: DateTime.now
                )
              end
            end
          end

          5.times do |usecase_index|
            unless params["uc#{usecase_index}name".to_sym].empty?
              _usecases = details.projects.find_by(name: project_name).usecases.find_by(name: params["uc#{usecase_index}name".to_sym])
              if _usecases
                # usecase with the name already exists
                success = false
                message = "Failed to add usecase as the usecase_name: #{usecase_index} already exists for project: #{project_name}"
              else
                details.projects.find_by(name: project_name).usecases << UseCase.new(
                  name: params["uc#{usecase_index}name".to_sym],
                  description: params["uc#{usecase_index}description".to_sym]
                )
                details.save
                # create requirements
                5.times do |req_index|
                  unless params["uc#{usecase_index}requirementdesc#{req_index}".to_sym].empty?
                    details.projects.find_by(name: project_name).usecases.find_by(name: params["uc#{usecase_index}name".to_sym]).requirements << Requirement.new(
                      requirement: params["uc#{usecase_index}requirementdesc#{req_index}".to_sym],
                      approch: params["uc#{usecase_index}approch#{req_index}".to_sym],
                      effort: params["uc#{usecase_index}effort#{req_index}".to_sym],
                      teameffort: params["uc#{usecase_index}teameffort#{req_index}".to_sym],
                      tools: params["uc#{usecase_index}tools#{req_index}".to_sym].split(','),
                      resources: params["uc#{usecase_index}resources#{req_index}".to_sym],
                      insights: params["uc#{usecase_index}insights#{req_index}".to_sym],
                      benefits: params["uc#{usecase_index}benefits#{req_index}".to_sym]
                    )
                  end
                end
              end
            end
          end
        end

        { success: success, msg: message }.to_json
      end

      # Generate's pdf format of the user's project information
      get '/consultant/:id/projects/generate' do |id|
        consultant = Consultant.find_by(email: id)
        consultant_name = "#{consultant.first_name.downcase}_#{consultant.last_name.downcase}"
        file_name = "#{consultant_name}_#{DateTime.now.strftime("%Y_%m_%d")}.pdf"

        # Make sure the file is opened in the browser window not downloadable
        headers "Content-Disposition" => "Inline; filename=#{file_name}",
                "Content-Type" => "application/pdf",
                "Content-Transfer-Encoding" => "binary"

        begin
          tmp_file = Tempfile.new(consultant_name)
          ProjectDocumentGenerator.new(
            consultant.id,
            tmp_file.path
          ).build!
          # output file contents
          tmp_file.read
        ensure
          tmp_file.close
        end
      end

      post '/consultant/:id/projects/update' do |consultant_id|
        # possible updates from here are: client, commercial_support [], current (false), duration,
        # management_tools [], software [], title
        project_id = params[:pk]
        update_key = params[:name]
        update_value = params[:value]
        success = true
        message = "Successfully updated #{update_key} to #{update_value}"

        begin
          consultant_details = Detail.find_by(consultant_id: consultant_id)
          consultant_details.projects.find_by(name: project_id).update_attribute(update_key.to_sym, update_value)
        rescue
          success = false
          message = "Failed to update(#{update_key})"
        end
        { success: success, msg: message }.to_json
      end

      post '/consultant/:id/projects/:project_id/usecases/update' do |consultant_id, project_id|
        usecase_id = params[:pk]
        update_key = params[:name]
        update_value = params[:value]
        success = true
        message = "Successfully updated #{update_key} to #{update_value}"

        begin
          consultant_details = Detail.find_by(consultant_id: consultant_id)
          consultant_details.projects.find_by(name: project_id).usecases.find_by(name: usecase_id).update_attribute(update_key.to_sym, update_value)
        rescue
          success = false
          message = "Failed to update(#{update_key})"
        end
        { success: success, msg: message }.to_json
      end

      post '/consultant/:id/projects/:project_id/usecases/:usecase_id/requirements/update' do |consultant_id, project_id, usecase_id|
        requirement_id = params[:pk]
        update_key = params[:name]
        update_value = params[:value]
        success = true
        message = "Successfully updated #{update_key} to #{update_value}"

        begin
          consultant_details = Detail.find_by(consultant_id: consultant_id)
          consultant_details.projects.find_by(name: project_id).usecases.find_by(name: usecase_id).requirements.find(requirement_id).update_attribute(update_key.to_sym, update_value)
        rescue
          success = false
          message = "Failed to update(#{update_key})"
        end
        { success: success, msg: message }.to_json
      end

      post '/consultant/:id/projects/:project_id/add_files' do |consultant_id, project_id|
        s_files = []
        w_files = []
        details = Detail.find_by(consultant_id: consultant_id)

        if params[:illustrations]
          params[:illustrations].each do |illustration|
            file_name = "#{consultant_id}_#{project_id}_#{Time.now.getutc.to_i}_#{illustration[:filename]}"
            illustration_id = upload_file(illustration[:tempfile], file_name)
            if illustration_id
              details.projects.find_by(name: project_id).illustrations << Illustration.new(
                  file_id: illustration_id,
                  filename: file_name,
                  uploaded_date: DateTime.now
              )
              s_files << file_name
            else
              w_files << file_name
            end
          end
        end
        # upload project documents if any
        if params[:documents]
          params[:documents].each do |document|
            file_name = "#{consultant_id}_#{project_id}_#{Time.now.getutc.to_i}_#{document[:filename]}"
            document_id = upload_file(document[:tempfile], file_name)
            if document_id
              details.projects.find_by(name: project_id).projectdocuments << ProjectDocument.new(
                  file_id: document_id,
                  filename: file_name,
                  uploaded_date: DateTime.now
              )
              s_files << file_name
            else
              w_files << file_name
            end
          end
        end
        flash[:info] = "Successfully uploaded files '#{s_files.join(',')}'" unless s_files.empty?
        flash[:warning] = "Failed uploading resume. Resume(s) with '#{w_files.join(',')}' already exists!." unless w_files.empty?
        redirect back
      end

    end
  end
end
