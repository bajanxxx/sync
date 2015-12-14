module Sync
  module Routes
    class Certifications < Base
      %w(/certifications /certifications/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/certifications' do
        protected!

        file = File.read(File.expand_path("../../assets/data/certifications.json", __FILE__))
        c_hash = JSON.parse(file)

        erb :certifications, locals: {
            c_hash: c_hash,
            pending_requests: CertificationRequest.where(status: 'pending'),
            approved_requests: CertificationRequest.where(status: 'approved'),
            disapproved_requests: CertificationRequest.where(status: 'disapproved'),
            passed_requests: CertificationRequest.where(status: 'completed', pass: true),
            failed_requests: CertificationRequest.where(status: 'completed', pass: false)
        }
      end

      post '/certifications/submit' do
        success    = true
        message    = "Certification Request submitted."

        file = File.read(File.expand_path("../../assets/data/certifications.json", __FILE__))
        c_hash = JSON.parse(file)

        consultant_first_name = params[:FirstName]
        consultant_last_name = params[:LastName]
        email = params[:Email]
        _ccode = params[:Certification]
        date = params[:Date]
        _f = params[:Flexible]
        flexible = if _f == 'on'
                     true
                   else
                     false
                   end
        time_preference = params[:TimePreference] # MNG | NOON
        c_details = c_hash.detect {|ele| ele['short'] == _ccode}

        CertificationRequest.create(
            consultant_first_name: consultant_first_name,
            consultant_last_name: consultant_last_name,
            consultant_email: email,
            booking_date: date,
            flexibility: flexible,
            time_preference: time_preference,
            name: c_details['name'],
            short: _ccode,
            code: c_details['code'],
            amount: c_details['price']
        )

        { success: success, msg: message }.to_json
      end

      post '/certifications/approve/:rid' do |rid|
        success    = true
        message    = 'Certification Request Approved.'

        fname = params[:fname]
        lname = params[:lname]
        date = params[:date]
        price = params[:price]
        notes = params[:notes]

        unless price =~ /^\d{1,4}\.\d{0,2}$/
          success = false
          message = 'Amount is not properly formatted'
        end

        if success
          cr = CertificationRequest.find(rid)
          cr.update_attributes(
            consultant_first_name: fname,
            consultant_last_name: lname,
            booking_date: date,
            status: 'approved',
            approved_by: @user.name,
            approved_at: DateTime.now,
            notes: notes
          )
          # immediate notification for the user
          Delayed::Job.enqueue(
              EmailRequestStatus.new(@settings, @user.name, cr, "Certification (#{cr.short})"),
              queue: 'consultant_certification_requests',
              priority: 10,
              run_at: 1.seconds.from_now
          )
          # prior day notification to users
          Delayed::Job.enqueue(
              EmailCertificationNotificationPriorDay.new(@settings, @user.name, cr),
              queue: 'consultant_certification_notifications',
              priority: 10,
              run_at: DateTime.strptime(cr.booking_date, '%m/%d/%Y') - 1
          )
          # post day notification to user about status of the certification
          Delayed::Job.enqueue(
              EmailCertificationNotificationPostDay.new(@settings, @user.name, cr),
              queue: 'consultant_certification_notifications',
              priority: 10,
              run_at: DateTime.strptime(cr.booking_date, '%m/%d/%Y') + 1
          )
          flash[:info] = 'Successfully approved and updated the user status of the request'
        end

        { success: success, msg: message }.to_json
      end

      post '/certifications/deny/:rid' do |rid|
        cr = CertificationRequest.find(rid)
        cr.update_attributes(status: 'disapproved', disapproved_by: @user.name, disapproved_at: DateTime.now)

        Delayed::Job.enqueue(
            EmailRequestStatus.new(@settings, @user.name, cr, "Certification (#{cr.short})"),
            queue: 'consultant_certification_requests',
            priority: 10,
            run_at: 1.seconds.from_now
        )
        flash[:info] = 'Successfully disapproved and updated the user status of the request'
        redirect '/documents'
      end

      # whether the consultant passed or not
      post '/certifications/status/pass/:rid' do |rid|
        cr = CertificationRequest.find(rid)
        cr.update_attributes(status: 'completed', pass: true)

        flash[:info] = 'Successfully marked request as pass'
      end

      post '/certifications/status/fail/:rid' do |rid|
        cr = CertificationRequest.find(rid)
        cr.update_attributes(status: 'completed', pass: false)

        flash[:info] = 'Successfully marked request as fail'
      end

      get '/certifications/report/generate' do
        protected!

        crs = CertificationRequest.all.entries

        content = "Certitication Name, Consultant Name,Status of request,Passed?,Amount,ApprovedDate,CertificationDate,Notes\n"

        crs.each do |cr|
          pass =  if cr.status == 'completed'
                    cr.pass ? 'PASSED' : 'FAILED'
                  else
                    'N/A'
                  end
          approved_at = if cr.status != 'pending'
                          if cr.status == 'approved'
                            cr.approved_at.strftime("%m/%d/%Y")
                          elsif cr.status == 'disapproved'
                            cr.disapproved_at.strftime("%m/%d/%Y")
                          elsif cr.status == 'completed'
                            cr.approved_at.strftime("%m/%d/%Y")
                          else
                            'N/A'
                          end
                        else
                          'N/A'
                        end

          content << "#{cr.name},#{cr.consultant_first_name} #{cr.consultant_last_name},#{cr.status},#{pass},#{cr.amount},#{approved_at},#{cr.booking_date},#{cr.notes}\n"
        end

        content_type :txt
        attachment "CertificationsReport_#{Date.today.strftime('%m-%d-%Y')}.csv"
        content
      end

      #
      # => Certification Requests (Consultant Routes)
      #

      get '/certifications/:userid' do |userid|
        self_protected!(userid)

        file = File.read(File.expand_path("../../assets/data/certifications.json", __FILE__))
        c_hash = JSON.parse(file)

        erb :consultant_certifications, locals: {
            c_hash: c_hash,
            consultant: Consultant.find_by(email: userid),
            pending_requests: CertificationRequest.where(consultant_email: userid, status: 'pending'),
            previous_requests: CertificationRequest.where(consultant_email: userid, :status.ne => 'pending')
        }
      end

      post '/certifications/:userid/request' do |userid|
        success    = true
        message    = 'Certifications Request submitted.'

        file = File.read(File.expand_path("../../assets/data/certifications.json", __FILE__))
        c_hash = JSON.parse(file)

        consultant_first_name = params[:FirstName]
        consultant_last_name = params[:LastName]
        _ccode = params[:Certification]
        date = params[:Date]
        _f = params[:Flexible]
        flexible = if _f == 'on'
                     true
                   else
                     false
                   end
        time_preference = params[:TimePreference] # MNG | NOON
        c_details = c_hash.detect {|ele| ele['short'] == _ccode}

        # validate date
        if Date.strptime(date, "%m/%d/%Y") < Date.today
          success = false
          message = 'Certification date should not be past'
        end

        # Check if the user already has the certification request made - check duplicates
        previous_cr = CertificationRequest.find_by(
            consultant_email: userid,
            short: _ccode
        )
        if previous_cr
          success = false
          message = 'Duplicate certification request, please contact admin to resolve the issue.'
        end

        # User cannot take more than one certification in a group
        similar_cr = CertificationRequest.any_of({ consultant_email: userid, :name => /.*#{c_details['authority']}.*/ })
        if similar_cr.count > 0
          success = false
          message = "Sorry, you cannot take another '#{c_details['authority']}' certification as you have already taken one its kind. Please contact admin for more details."
        end

        if success
          cr = CertificationRequest.create(
              consultant_first_name: consultant_first_name,
              consultant_last_name: consultant_last_name,
              consultant_email: userid,
              booking_date: date,
              flexibility: flexible,
              time_preference: time_preference,
              name: c_details['name'],
              short: _ccode,
              code: c_details['code'],
              amount: c_details['price']
          )
          # Send email to the admin group
          Delayed::Job.enqueue(
              EmailCertificationRequest.new(@settings, @user.name, cr),
              queue: 'consultant_certification_requests',
              priority: 10,
              run_at: 1.seconds.from_now
          )
          # Send an sms to the admin
          @settings[:admin_phone].each do |to_phone|
            twilio.account.messages.create(
                from: @settings[:twilio_phone],
                to: to_phone,
                body: "SYNC: #{consultant_first_name} #{consultant_last_name} certification booking request"
            )
          end
        end

        { success: success, msg: message }.to_json
      end
    end
  end
end