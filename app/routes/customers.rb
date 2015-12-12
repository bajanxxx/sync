module Sync
  module Routes
    class Customers < Base
      %w(/customers /customers/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/customers' do
        protected!

        data = []
        Customer.only(:first_name, :last_name, :company, :phone, :industry).each do |c|
          data << [ c.first_name, c.last_name, c.company, c.phone, c.industry || "NA" ]
        end
        erb :customers, locals: {
          customers_data: data
        }
      end

      # Add a new vendor
      post '/customer/new' do
        first_name = params[:FirstName]
        last_name  = params[:LastName]
        email      = params[:Email]
        company    = params[:Company]
        company_id = params[:UniqueCompanyID] || "00000"
        is_business_unit_id_head = params[:BusinessUnitITHead] || "NA"
        title         = params[:Title]
        address_line1 = params[:AddressLine1] || "NA"
        address_line2 = params[:AddressLine2] || "NA"
        city          = params[:City] || "NA"
        state         = params[:State] || "NA"
        zip           = params[:Zip] || 00000
        phone         = params[:Phone] || "NA"
        extension     = params[:Ext] || "NA"
        fax           = params[:Fax] || "NA"
        industry      = params[:Industry] || "NA"
        it_budget_million = params[:ITBudgetM] || 0.00
        it_employees = params[:ITEmployees] || 0
        revenue_billion = params[:RevenueB] || 0.00
        fiscal_year_end = params[:FiscalYearEnd] || "NA"
        duns = params[:DUNS] || "NA"

        success    = true
        message    = "Successfully added vendor with email: #{email}"

        if first_name.empty? || last_name.empty? || email.empty? || company.empty? || title.empty?
          success = false
          message = "'firstname', 'lastname', 'email', 'company' and 'title' cannot be empty"
        else
          _customer = Customer.find_by(email: email)
          if _customer
            success = false
            message = "Customer already exists with email address: #{email}"
          else
            success = true
            Customer.create(
                company_id: company_id,
                company: company,
                first_name: first_name,
                last_name: last_name,
                is_business_unit_id_head: is_business_unit_id_head,
                title: title,
                address_line1: address_line1,
                address_line2: address_line2,
                city: city,
                state: state,
                zip: zip,
                phone: phone,
                extension: extension,
                fax: fax,
                email: email,
                industry: industry,
                it_budget_million: it_budget_million,
                it_employees: it_employees,
                revenue_billion: revenue_billion,
                fiscal_year_end: fiscal_year_end,
                duns: duns
            )
          end
        end

        { success: success, msg: message }.to_json
      end

      # Parse csv, tsv file and upload them to mongo
      post '/customers/bulkadd' do
        parsed_records = 0
        failed_records = 0
        new_records_inserted = 0
        duplicate_records = 0
        csv = begin
          CSV.parse(File.read(params[:file][:tempfile]), headers: true)
        rescue ArgumentError # Hanfle UTF-8 errors
          CSV.parse(File.open(params[:file][:tempfile], "r:ISO-8859-1"), headers: true)
        end
        csv.each do |customer|
          if customer['Email']
            if customer.fetch('Email') =~ @email_regex
              parsed_records += 1
              _customer = Customer.find_by(email: customer.fetch('Email'))
              if _customer
                duplicate_records += 1
              else
                new_records_inserted += 1
                Customer.create(
                    company_id: customer['UniqueCompanyID'],
                    company: customer['Company'],
                    first_name: customer['First Name'],
                    last_name: customer['Last Name'],
                    has_gatekeeper: customer['Has Gatekeeper'],
                    is_business_unit_id_head: customer['Business Unit I.T. Head'],
                    title: customer['Title'],
                    address_line1: customer['Address Line 1'],
                    address_line2: customer['Address Line 2'],
                    city: customer['City'],
                    state: customer['State'],
                    zip: customer['Zip'],
                    phone: customer['Phone'],
                    extension: customer['Ext'],
                    fax: customer['Fax'],
                    email: customer['Email'],
                    industry: customer['Industry'],
                    it_budget_million: customer['I.T. Budget($M)'],
                    it_employees: customer['I.T. Employees'],
                    revenue_billion: customer['Revenue($B)'],
                    fiscal_year_end: customer['Fiscal Year End'],
                    duns: customer['DUNS']
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