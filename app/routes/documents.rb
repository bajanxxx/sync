module Sync
  module Routes
    class Documents < Base
      %w(/documents /documents/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/documents' do
        protected!

        erb :documents, locals: {
            templates:            DocumentTemplate.all,
            signatures:           DocumentSignature.all,
            layouts:              DocumentLayout.all,
            pending_requests:     DocumentRequest.where(status: 'pending'),
            approved_requests:    DocumentRequest.where(status: 'approved'),
            disapproved_requests: DocumentRequest.where(status: 'disapproved'),
        }
      end

      get '/documents/templates' do
        protected!

        erb :doc_templates, locals: {
            templates:  DocumentTemplate.all,
            signatures: DocumentSignature.all,
            layouts:    DocumentLayout.all
        }
      end

      post '/documents/templates' do
        # puts CGI.unescapeHTML(params["body"])
        template_name = params[:name]
        template_body = params[:body]
        template_type = if params[:ol] == 'true'
                          'OL'
                        elsif params[:ll] == 'true'
                          'LL'
                        elsif params[:evl] == 'true'
                          'EVL'
                        elsif params[:rl] == 'true'
                          'RL'
                        elsif params[:ta] == 'true'
                          'TA'
                        elsif params[:si] == 'true'
                          'SI'
                        end
        success    = true
        message    = "Successfully added email template with name: #{template_name} and type: #{template_type}"

        if template_name.empty? || template_body.empty? || template_type.empty?
          success = false
          message = "fields cannot be empty"
        else
          _doc_template = DocumentTemplate.find_by(name: template_name)
          if _doc_template
            success = false
            message = "Template already exists with name: #{template_name}"
          else
            # Create the actual tempalte
            DocumentTemplate.create(
                name: template_name,
                type: template_type,
                content: template_body,
            )
          end
        end

        { success: success, msg: message }.to_json
      end

      post '/documents/templates/:id/update_template' do |id|
        template_type = params[:type]
        template_body = params[:body]
        success    = true
        message    = 'Successfully updated template'

        if template_body.empty? || template_type.empty?
          success = false
          message = 'fields cannot be empty'
        else
          _template = DocumentTemplate.find_by(_id: id)
          if !_template
            success = false
            message = 'Something went wrong, document not found!!!'
          else
            _template.update_attributes(
                type: template_type,
                content: template_body
            )
          end
        end
        { success: success, msg: message }.to_json
      end

      # Deletes document template
      delete '/documents/templates/:id' do |id|
        DocumentTemplate.find_by(_id: id).delete
      end

      post '/documents/signatures/add' do
        signature_file = params[:file][:tempfile]
        file_name = params[:file][:filename]
        file_type = params[:file][:type]
        signature_id = upload_file(signature_file, file_name)
        if signature_id
          DocumentSignature.create(
              file_id: signature_id,
              filename: file_name,
              uploaded_date: DateTime.now,
              type: file_type
          )
          flash[:info] = "Uploaded sucessfully #{signature_id}"
        else
          flash[:warning] = "Failed uploading signature. Signature with #{file_name} already exists!."
        end
        redirect back
      end

      post '/documents/layouts/add' do
        layout_file = params[:file][:tempfile]
        file_name = params[:file][:filename]
        file_type = params[:file][:type]
        layout_id = upload_file(layout_file, file_name)
        if layout_id
          DocumentLayout.create(
              file_id: layout_id,
              filename: file_name,
              uploaded_date: DateTime.now,
              type: file_type
          )
          flash[:info] = "Uploaded sucessfully #{layout_id}"
        else
          flash[:warning] = "Failed uploading layout. Layout with #{file_name} already exists!."
        end
        redirect back
      end

      # Render image with specified dimensions (size like 100x100)
      # this route resolve's to /documents/signatures/id/render
      # also resolves to /documents/signatures/id/render/200x200
      get '/documents/signatures/:id/render/?:size?' do |id, size|
        image_prps = DocumentSignature.find_by(file_id: id)
        image_file = grid.get(BSON::ObjectId(id)).read
        image = MiniMagick::Image.read(image_file)
        image.resize(size || '100x100')
        send_file(image.path, type: image_prps.type, disposition: 'inline')
      end

      get '/documents/layouts/:id/render/?:size?' do |id, size|
        image_prps = DocumentLayout.find_by(file_id: id)
        image_file = grid.get(BSON::ObjectId(id)).read
        image = MiniMagick::Image.read(image_file)
        image.resize(size || '100x100')
        send_file(image.path, type: image_prps.type, disposition: 'inline')
      end

      post '/documents/send/:type' do |document_type|
        cname = params[:name]
        email = params[:email]
        company = params[:company]
        position = params[:position]
        start_date = params[:sdate]
        end_date = params[:edate]
        dated = params[:dated]
        tname = params[:tname]
        sname = params[:sname]
        lname = params[:layout]
        rid = params[:rid] # open present if this a request from consultant
        document_format = ''
        namespace = nil
        everify = if company =~/Cloudwick|cloudwick/
                    642485
                  else
                    270262
                  end
        location = if company =~/Cloudwick|cloudwick/
                     'Newark, California'
                   else
                     'Hayward, California'
                   end
        success    = true
        message    = "Successfully sent #{document_type} to #{email}"

        begin
          signature_id = DocumentSignature.find_by(filename: sname).file_id
          layout_id = DocumentLayout.find_by(filename: lname).file_id

          case document_type
            when 'leaveletter'
              if Date.strptime(start_date, "%m/%d/%Y") > Date.strptime(end_date, "%m/%d/%Y")
                success = false
                message = 'start date should be less than end date'
              end
              document_format = 'LEAVELETTER'
              namespace = OpenStruct.new(
                  name: cname,
                  start_date: start_date,
                  end_date: end_date,
                  position: position,
                  company: company,
                  location: location,
                  companyid: everify,
                  dated_as: dated
              )
              # Build an erb template and replace variables
              template_content = DocumentTemplate.find_by(name: tname).content
              erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
              template = ERB.new(erb_template).result(namespace.instance_eval {binding})

              generate_document_opts = {
                  cname: cname,
                  company: company,
                  signature_id: signature_id,
                  layout_id: layout_id,
                  start_date: start_date,
                  end_date: end_date,
                  dated: dated,
                  template: template
              }
            when 'offerletter'
              document_format = 'OFFERLETTER'
              namespace = OpenStruct.new(
                  name: cname,
                  start_date: start_date,
                  position: position,
                  li: '•',
                  company: company,
                  companyid: everify,
                  location: location,
                  dated_as: dated
              )
              # Build an erb template and replace variables
              template_content = DocumentTemplate.find_by(name: tname).content
              erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
              template = ERB.new(erb_template).result(namespace.instance_eval {binding})

              generate_document_opts = {
                  cname: cname,
                  company: company,
                  signature_id: signature_id,
                  layout_id: layout_id,
                  start_date: start_date,
                  dated: dated,
                  template: template
              }
            when 'employmentletter'
              document_format = 'EMPLOYMENTLETTER'
              namespace = OpenStruct.new(
                  name: cname,
                  start_date: start_date,
                  position: position,
                  companyid: everify,
                  company: company,
                  location: location,
                  start_date: start_date,
                  dated_as: dated
              )
              # Build an erb template and replace variables
              template_content = DocumentTemplate.find_by(name: tname).content
              erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
              template = ERB.new(erb_template).result(namespace.instance_eval {binding})

              generate_document_opts = {
                  cname: cname,
                  company: company,
                  signature_id: signature_id,
                  layout_id: layout_id,
                  start_date: start_date,
                  dated: dated,
                  template: template
              }

          end

          if email !~ @email_regex
            success = false
            message = "email not formatted properly"
          else
            Delayed::Job.enqueue(
                GenerateDocument.new(email, @settings, document_format, @user.name,
                                     grid.get(BSON::ObjectId(signature_id)).read,
                                     grid.get(BSON::ObjectId(layout_id)).read,
                                     generate_document_opts
                ),
                queue: 'consultant_document_requests',
                priority: 10,
                run_at: 1.seconds.from_now
            )
            # If this a request made by consultant mark the status of the request
            if rid
              DocumentRequest.find(rid).update_attributes(
                  status: 'approved',
                  approved_by: @user.name,
                  approved_at: DateTime.now
              )
            end
            success = true
            message = "Sucessfully sent #{document_type} to #{cname}"
          end
        rescue ArgumentError
          success = false
          message = "Cannot parse date format (expected format: mm/dd/yyyy)"
        end
        flash[:info] = message
        { success: success, msg: message }.to_json
      end

      # send the documents to admin instead
      # TODO: replace this with download/preview of documents
      post '/documents/send/:type/admin' do |document_type|
        cname = params[:name]
        email = params[:email]
        company = params[:company]
        position = params[:position]
        start_date = params[:sdate]
        end_date = params[:edate]
        dated = params[:dated]
        tname = params[:tname]
        sname = params[:sname]
        lname = params[:layout]
        rid = params[:rid] # open present if this a request from consultant
        everify = if company =~/Cloudwick|cloudwick/
                    642485
                  else
                    270262
                  end
        location = if company =~/Cloudwick|cloudwick/
                     'Newark, California'
                   else
                     'Hayward, California'
                   end
        document_format = ''
        namespace = nil

        success    = true
        message    = "Successfully sent #{document_type} to #{email}"

        begin
          signature_id = DocumentSignature.find_by(filename: sname).file_id
          layout_id = DocumentLayout.find_by(filename: lname).file_id

          case document_type
            when 'leaveletter'
              if Date.strptime(start_date, "%m/%d/%Y") > Date.strptime(end_date, "%m/%d/%Y")
                success = false
                message = "start date should be less than end date"
              end
              document_format = 'LEAVELETTER'
              namespace = OpenStruct.new(
                  name: cname,
                  start_date: start_date,
                  end_date: end_date,
                  position: position,
                  company: company,
                  location: location,
                  companyid: everify,
                  dated_as: dated
              )
              # Build an erb template and replace variables
              template_content = DocumentTemplate.find_by(name: tname).content
              erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
              template = ERB.new(erb_template).result(namespace.instance_eval {binding})

              generate_document_opts = {
                  cname: cname,
                  company: company,
                  signature_id: signature_id,
                  layout_id: layout_id,
                  start_date: start_date,
                  end_date: end_date,
                  dated: dated,
                  template: template
              }
            when 'offerletter'
              document_format = 'OFFERLETTER'
              namespace = OpenStruct.new(
                  name: cname,
                  start_date: start_date,
                  position: position,
                  li: '•',
                  company: company,
                  companyid: everify,
                  location: location,
                  dated_as: dated
              )
              # Build an erb template and replace variables
              template_content = DocumentTemplate.find_by(name: tname).content
              erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
              template = ERB.new(erb_template).result(namespace.instance_eval {binding})

              generate_document_opts = {
                  cname: cname,
                  company: company,
                  signature_id: signature_id,
                  layout_id: layout_id,
                  start_date: start_date,
                  dated: dated,
                  template: template
              }
            when 'employmentletter'
              document_format = 'EMPLOYMENTLETTER'
              namespace = OpenStruct.new(
                  name: cname,
                  start_date: start_date,
                  position: position,
                  companyid: everify,
                  company: company,
                  location: location,
                  dated_as: dated
              )
              # Build an erb template and replace variables
              template_content = DocumentTemplate.find_by(name: tname).content
              erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
              template = ERB.new(erb_template).result(namespace.instance_eval {binding})

              generate_document_opts = {
                  cname: cname,
                  company: company,
                  signature_id: signature_id,
                  layout_id: layout_id,
                  start_date: start_date,
                  dated: dated,
                  template: template
              }

          end

          if email !~ @email_regex
            success = false
            message = "email not formatted properly"
          else
            Delayed::Job.enqueue(
                GenerateDocument.new(@session_username, @settings, document_format, @user.name,
                                     grid.get(BSON::ObjectId(signature_id)).read,
                                     grid.get(BSON::ObjectId(layout_id)).read,
                                     generate_document_opts
                ),
                queue: 'consultant_document_requests',
                priority: 10,
                run_at: 1.seconds.from_now
            )
            success = true
            message = "Sucessfully sent #{document_type} to #{@session_username}"
          end
        rescue ArgumentError
          success = false
          message = "Cannot parse date format (expected format: mm/dd/yyyy)"
        end
        { success: success, msg: message }.to_json
      end

      post '/documents/requests/deny/:id' do |rid|
        dr = DocumentRequest.find(rid)
        dr.update_attributes(status: 'disapproved', disapproved_by: @user.name, disapproved_at: DateTime.now)
        Delayed::Job.enqueue(
            EmailRequestStatus.new(@settings, @user.name, dr, "Document (#{dr.document_type})"),
            queue: 'consultant_document_requests',
            priority: 10,
            run_at: 1.seconds.from_now
        )
        flash[:info] = 'Sucessfully disapproved and updated the user status of the request'
        redirect "/documents"
      end

      #
      # => Document Requests (Consultant Routes)
      #

      get '/documents/:userid' do |userid|
        self_protected!(userid)

        erb :consultant_documents,
            locals: {
                consultant: Consultant.find_by(email: userid),
                pending_requests: DocumentRequest.where(consultant_email: userid, status: 'pending'),
                previous_requests: DocumentRequest.where(consultant_email: userid, :status.ne => 'pending')
            }
      end

      post '/documents/:userid/request' do |userid|
        success    = true
        message    = 'Successfully created a requests'

        fullname = params[:fullname]
        email = userid
        company = params[:company]
        position = params[:position]
        document_type = params[:documenttype]
        llstartdate = params[:llstartdate]
        llenddate = params[:llenddate]
        lldatedas = params[:lldatedas]
        olstartdate = params[:olstartdate]
        oldatedas = params[:oldatedas]
        elstartdate = params[:elstartdate]
        eldatedas = params[:eldatedas]

        %w(fullname company position).each do |param|
          if params[param.to_sym].empty?
            success = false
            message = "Param '#{param}' cannot be empty"
          end
        end

        if !%w(LL OL EVL RL).include?(document_type)
          success = false
          message = 'Select an appropriate document type'
        else
          case document_type
            when 'LL'
              if llstartdate.empty? || llenddate.empty? || lldatedas.empty?
                success = false
                message = 'Must provide start, end and dated as dates for a leave letter'
              elsif Date.strptime(llstartdate, "%m/%d/%Y") > Date.strptime(llenddate, "%m/%d/%Y")
                success = false
                message = 'Start date of leaveletter should be before end date'
              end
            when 'OL'
              if olstartdate.empty? || oldatedas.empty?
                success = false
                message = 'Must provide startdate end dated as dates for offer letter'
              end
            when 'EVL'
              if elstartdate.empty? || eldatedas.empty?
                success = false
                message = 'Must provide startdate end dated as dates for employment letter'
              end
          end
        end

        if success
          case document_type
            when 'LL'
              dr = DocumentRequest.create(
                  consultant_name: fullname,
                  consultant_email: email,
                  position: position,
                  document_type: document_type,
                  start_date: llstartdate,
                  end_date: llenddate,
                  dated: lldatedas,
                  company: company
              )
            when 'OL'
              dr = DocumentRequest.create(
                  consultant_name: fullname,
                  consultant_email: email,
                  position: position,
                  document_type: document_type,
                  start_date: olstartdate,
                  dated: oldatedas,
                  company: company
              )
            when 'EVL'
              dr = DocumentRequest.create(
                  consultant_name: fullname,
                  consultant_email: email,
                  position: position,
                  document_type: document_type,
                  start_date: elstartdate,
                  dated: eldatedas,
                  company: company
              )
          end
          # Send email to the admin group
          Delayed::Job.enqueue(
              EmailDocumentRequest.new(@settings, @user.name, dr),
              queue: 'consultant_document_requests',
              priority: 10,
              run_at: 1.seconds.from_now
          )
          # Send an sms to the admin
          @settings[:admin_phone].each do |to_phone|
            twilio.account.messages.create(
                from: @settings[:twilio_phone],
                to: to_phone,
                body: "SYNC: #{fullname} requested document: (#{document_type})"
            )
          end
        end

        { success: success, msg: message }.to_json
      end

    end
  end
end