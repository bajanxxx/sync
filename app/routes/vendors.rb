module Sync
  module Routes
    class Vendors < Base
      %w(/vendors /vendors/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/vendors' do
        protected!

        data = []
        Vendor.only(:first_name, :last_name, :company, :phone, :email).each do |v|
          data << [ v.first_name || 'NA', v.last_name || 'NA', v.company || 'NA' , v.phone || 'NA', v.email ]
        end
        erb :vendors, :locals => { vendors_data: data }
      end

      # Add a new vendor
      post '/vendor/new' do
        first_name = params[:FirstName]
        last_name  = params[:LastName]
        email      = params[:Email]
        company    = params[:Company]
        phone      = params[:Phone]
        success    = true
        message    = "Successfully added vendor with email: #{email}"

        if first_name.empty? || last_name.empty? || email.empty?
          success = false
          message = "fields cannot be empty"
        else
          _vendor = Vendor.find_by(email: email)
          if _vendor
            success = false
            message = "Vendor already exists with email address: #{email}"
          else
            Vendor.create(
                first_name: first_name,
                last_name: last_name,
                email: email,
                company: company,
                phone: phone
            )
          end
        end

        { success: success, msg: message }.to_json
      end

      # Parse csv, tsv file and upload them to mongo
      post '/vendors/bulkadd' do
        parsed_records = 0
        failed_records = 0
        new_records_inserted = 0
        duplicate_records = 0
        csv = CSV.parse(File.read(params[:file][:tempfile]), headers: true)
        csv.each do |vendor|
          if vendor['email']
            if vendor.fetch('email') =~ @email_regex
              parsed_records += 1
              _vendor = Vendor.find_by(email: vendor.fetch('email'))
              if _vendor
                duplicate_records += 1
              else
                new_records_inserted += 1
                Vendor.create(
                    email: vendor['email'],
                    first_name: vendor['first_name'],
                    last_name: vendor['last_name'],
                    company: vendor['company'],
                    phone: vendor['phone']
                )
              end
            end
          else
            failed_records += 1
          end
        end
        message = "Parsed: #{parsed_records}, invalid-records: #{failed_records},"\
      " inserted-records: #{new_records_inserted}, duplicate-records: #{duplicate_records}."

        flash[:info] = message
        redirect back
      end

    end
  end
end