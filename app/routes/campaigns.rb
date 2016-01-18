module Sync
  module Routes
    class Campaigns < Base

      before '/campaign' do
        redirect '/login' unless @session_username
      end

      # NOTE: This is causing the mailgun /campign/opens to fail
      # before '/campaign/*' do
      #   redirect '/login' if !@session_username
      # end

      get '/campaign' do
        protected!

        Campaign.all.each do |campaign|
          get_campaign_stats(campaign._id)
        end
        erb :campaign, locals: {
          templates: Template.all,
          active_campaigns: Campaign.where(active: true).all,
          all_campaign_stats: get_campaign_sent_events,
          customer_groups: Customer.distinct(:industry).compact,
          customer: Customer
        }
      end

      get '/campaign/templates' do
        protected!

        erb :campaign_templates, locals: { templates: Template.all }
      end

      get '/campaign/templates/render/:id' do |id|
        Template.find(id).content
      end

      post '/campaign/email_template' do
        template_name = params[:name]
        template_subject = params[:subject]
        template_body = params[:body]
        success    = true
        message    = "Successfully added email template with name: #{template_name}"

        if template_name.empty? || template_body.empty? || template_subject.empty?
          success = false
          message = "fields cannot be empty"
        else
          _template = Template.find_by(name: template_name)
          if _template
            success = false
            message = "Template already exists with name: #{template_name}"
          else
            success = true
            # Create a new campaign for tacking all the events
            create_campaign(template_name, template_name.downcase.gsub(' ', '_'))
            # Create a new route to handle replies to this campaign
            create_route('customer')
            create_route('vendor')
            # Check if the content is html
            html_only = if template_body =~ /^s*<[^Hh>]*html/
                          true
                        else
                          false
                        end
            # Create the actual template
            Template.create(
                name: template_name,
                subject: template_subject,
                content: template_body,
                html: html_only
            )
          end
        end

        { success: success, msg: message }.to_json
      end

      post '/campaign/email_template/:id/update_content' do |id|
        template_subject = params[:subject]
        template_body = params[:body]
        success    = true
        message    = 'Successfully updated email template'

        if template_body.empty? || template_subject.empty?
          success = false
          message = 'fields cannot be empty'
        else
          _template = Template.find_by(_id: id)
          if _template
            html_only = if template_body =~ /^s*<[^Hh>]*html/
                          true
                        else
                          false
                        end
            template.update_attributes(
                subject: template_subject,
                content: template_body,
                html: html_only
            )
          else
            success = false
            message = 'Something went wrong, document not found!!!'
          end
        end
        { success: success, msg: message }.to_json
      end

      # Deletes email template and its associated campaign
      delete '/campaign/email_template/:id' do |id|
        template = Template.find_by(_id: id)
        template.delete
        Campaign.where(_id: template.name.downcase.gsub(' ', '_')).update(active: false)
        delete_campaign(template.name.downcase.gsub(' ', '_'))
      end

      # Start an email campaign using the vendors list we have and keep track of replied, bounces, spam
      post '/campaign/vendor/start' do
        # {"name"=>"First Template|(Cloudwick Reaching Out)", "all_vendors"=>"true", "replied_vendors_only"=>"false"}
        template_name = params[:name].split('|').first
        all_vendors = params[:all_vendors]
        replied_vendors_only = params[:replied_vendors_only]
        success    = true
        message    = "Starting Campaign..."

        message = VendorCampaign.new(@settings, template_name, all_vendors, replied_vendors_only).start

        flash[:info] = "Starting campaign '#{params[:name]}'. #{message}"
        { success: success, msg: message }.to_json
      end

      post '/campaign/customer/start' do
        # {"name"=>"Test|(Test)", "customer_industry"=>"Aerospace & Defense", "replied_customers_only"=>"false"}
        template_name = params[:name].split('|').first
        customer_vertical = params[:customer_industry]
        replied_customers_only = params[:replied_customers_only]
        nodups = params[:nodups]
        success = true
        message = 'Starting Campaign...'

        message = CustomerCampaign.new(@settings, template_name, customer_vertical, replied_customers_only, nodups).start

        flash[:info] = "Starting campaign '#{params[:name]}'. #{message}"
        { success: success, msg: message }.to_json
      end

      # Handle vendor email replies sent using campaign
      post '/campaign/vendor/reply' do
        puts "Email received from #{params['recipient']}, processing..."
        # Get the campaign information that this reply belongs to
        existing_campaigns = Campaign.only(:_id).all.entries.map(&:_id)
        references =  if params['References']
                        params['References'].scan(/<(.*?)>/).flatten
                      else
                        []
                      end
        possible_campaign = existing_campaigns.map { |c| c if references.map{ |r| r.split('@').first }.include?(c) }.compact
        campaign_id = if possible_campaign.empty?
                        'Uncategozired'
                      else
                        possible_campaign.first
                      end
        email = Email.create(
            recipient: params['recipient'],
            sender: params['sender'],
            subject: params['subject'],
            from: params['From'],
            received: params['Received'],
            stripped_text: params['stripped-text'],
            stripped_signature: params['stripped-signature'],
            message_id: params['Message-Id'],
            campaign_id: campaign_id,
            attachments_count: params['attachment-count'] || 0
        )
        unless campaign_id == 'Uncategozired'
          Campaign.find_by(_id: campaign_id).push(:replies, email.id)
        end
        # Upload attachments
        attachment_count = params['attachment-count'].to_i
        if attachment_count > 0
          attachment_count.times do |index|
            attachment_tmp_file = params["attachment-#{index+1}"][:tempfile]
            attachment_filename = params["attachment-#{index+1}"][:filename]
            attachment_id = upload_file(attachment_tmp_file, attachment_filename)
            email.attachments.create(
                _id: attachment_id,
                filename: attachment_filename,
                uploaded_date: DateTime.now
            )
          end
        end
        status 200
      end

      # Handle vendor email replies sent using campaign
      post '/campaign/customer/reply' do
        puts "Email received from #{params['recipient']}, processing..."
        # Get the campaign information that this reply belongs to
        existing_campaigns = Campaign.only(:_id).all.entries.map(&:_id)
        references =  if params['References']
                        params['References'].scan(/<(.*?)>/).flatten
                      else
                        []
                      end
        possible_campaign = existing_campaigns.map { |c| c if references.map{ |r| r.split('@').first }.include?(c) }.compact
        campaign_id = if possible_campaign.empty?
                        'Uncategozired'
                      else
                        possible_campaign.first
                      end
        email = Email.create(
            recipient: params['recipient'],
            sender: params['sender'],
            subject: params['subject'],
            from: params['From'],
            received: params['Received'],
            stripped_text: params['stripped-text'],
            stripped_signature: params['stripped-signature'],
            message_id: params['Message-Id'],
            campaign_id: campaign_id,
            attachments_count: params['attachment-count'] || 0
        )
        unless campaign_id == 'Uncategozired'
          Campaign.find_by(_id: campaign_id).push(:replies, email.id)
        end
        # Upload attachments
        attachment_count = params['attachment-count'].to_i
        if attachment_count > 0
          attachment_count.times do |index|
            attachment_tmp_file = params["attachment-#{index+1}"][:tempfile]
            attachment_filename = params["attachment-#{index+1}"][:filename]
            attachment_id = upload_file(attachment_tmp_file, attachment_filename)
            email.attachments.create(
                _id: attachment_id,
                filename: attachment_filename,
                uploaded_date: DateTime.now
            )
          end
        end
        status 200
      end

      # Handle email unsubscribes
      post '/campaign/unsubscribe' do
        unsubscribers = get_campaign_unsubscribers
        if unsubscribers
          unsubscribers[:items].each do |unsubscriber|
            unsubscriber_email = unsubscriber[:address]
            puts "Got unsubscribe back from #{unsubscriber_email}"
            _vendor = Vendor.where(email: unsubscriber_email)
            _vendor.update(unsubscribed: true) if _vendor
            _customer = Customer.where(email: unsubscriber_email)
            _customer.update(unsubscribed: true) if _customer
          end
        end
        status 200
      end

      # Handle spam clicks
      post '/campaign/complaints' do
        puts params
      end

      # Handle email bounce (delete's the respective email)
      post '/campaign/bounce' do
        bounces = get_campaign_bounces
        if bounces
          bounces[:items].each do |bounce|
            email = bounce[:address]
            puts "Got bounce back from #{email}"
            _vendor = Vendor.where(email: email)
            _customer = Customer.where(email: email)
            _vendor.update(bounced: true) if _vendor
            _customer.update(bounced: true) if _customer
          end
        end
        status 200
      end

      # Fetch the events for a specified campaign
      post '/campaign/events' do
        puts params
      end

      # Handle opens
      post '/campaign/opens' do
        puts "Processing email open from #{params['recipient']}"
        Tracking.create(
            recipient: params['recipient'],
            domain: params['domain'],
            device_type: params['device-type'],
            country: params['country'],
            region: params['region'],
            city: params['city'],
            client_name: params['client-name'],
            user_agent: params['user-agent'],
            client_os: params['client-os'],
            ip: params['ip'],
            client_type: params['client-type'],
            event: params['event'],
            timestamp: params['timestamp'],
            campaign_id: params['campaign-id'] || ""
        )
        status 200
      end

      # Handle clicks
      post '/campaign/clicks' do
        puts "Processing email click from #{params['recipient']}"
        Tracking.create(
            recipient: params['recipient'],
            domain: params['domain'],
            device_type: params['device-type'],
            country: params['country'],
            region: params['region'],
            city: params['city'],
            client_name: params['client-name'],
            user_agent: params['user-agent'],
            client_os: params['client-os'],
            ip: params['ip'],
            client_type: params['client-type'],
            event: params['event'],
            timestamp: params['timestamp'],
            campaign_id: params['campaign-id'] || ""
        )
        status 200
      end
    end
  end
end