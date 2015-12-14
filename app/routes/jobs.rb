module Sync
  module Routes
    class Jobs < Base
      %w(/jobs /jobs/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/jobs' do
        protected!

        # Build job stats per source and search term like total jobs for a given date, read jobs per
        # given date
        jobs = Hash.new { |hash, key| hash[key] = {} }

        Job::SOURCES.each do |source|
          Job::SEARCH_TERMS.each do |search_term|
            jobs[source][search_term] = {}
            _jobs = Job.public_send("#{source.to_s}_#{search_term.to_s}_jobs_week")
            _dates_posted = _jobs.only(:date_posted).map { |j| j.date_posted }.uniq
            _dates_posted.each do |_date|
              jobs[source][search_term][_date.strftime('%Y-%m-%d').to_sym] = {total: 0, read: 0, followup: 0}
            end
            _jobs.each do |_job|
              date = _job.date_posted.strftime('%Y-%m-%d').to_sym
              jobs[source.to_sym][search_term.to_sym][date][:total] += 1
              if _job.read == true
                jobs[source.to_sym][search_term.to_sym][date][:read] += 1
              end
              _job.applications.each do |app|
                if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
                  jobs[source.to_sym][search_term.to_sym][date][:followup] += 1
                end
              end
            end
          end
        end

        erb :jobs, :locals => { :jobs => jobs }
      end

      # Create a new job posting
      post '/job/new' do
        success = true
        message = 'Successfully added job'

        params.keys.each do |p|
          if params[p].empty?
            success = false
            message = 'Required fields are not present'
          end
        end

        if success
          _job = Job.find_by(url: params[:URL])
          if _job
            success = false
            message = "Job already exists with url: #{params[:URL]}"
          else
            date = DateTime.now.strftime("%Y-%m-%d")
            Job.find_or_create_by(url: params[:URL], date_posted: date) do |doc|
              doc.source      = "INTERNAL"
              doc.url         = params[:URL]
              doc.search_term = params[:SearchString].downcase
              doc.date_posted = date
              doc.title       = params[:JobTitle]
              doc.company     = params[:Company]
              doc.location    = params[:Location]
              doc.skills      = params[:Skills]
              doc.emails      = params[:Emails]
              doc.phone_nums  = params[:Phones]
              doc.desc        = params[:Desc]
            end
            success = true
          end
        end

        { success: success, msg: message }.to_json
      end

      get '/jobs/:date' do |date|
        protected!

        categorized_jobs = Hash.new { |hash, key| hash[key] = {} }

        Job::SOURCES.each do |source|
          Job::SEARCH_TERMS.each do |search_term|
            #jobs = Job.where(search_term: search_term, source: source.upcase, date_posted: date, hide: false)
            jobs = Job.public_send("#{source.to_s}_#{search_term.to_s}_jobs_day", date)

            read_postings = Hash.new { |hash, key| hash[key] = {} }
            unread_postings = Hash.new { |hash, key| hash[key] = {} }
            jobs.each do |job|
              job_sym = job.id.to_s.to_sym
              if job.read
                read_postings[job_sym][:o] = job
                read_postings[job_sym][:tracking] = []
                job.applications.each do |app|
                  c = app.consultant
                  read_postings[job_sym][:tracking] << c.first_name[0..0].capitalize + c.last_name[0..0].capitalize
                end
              else
                unread_postings[job_sym][:o] = job
                unread_postings[job_sym][:tracking] = []
                job.applications.each do |app|
                  c = app.consultant
                  unread_postings[job_sym][:tracking] << c.first_name[0..0].capitalize + c.last_name[0..0].capitalize
                end
              end
            end # end jobs.each

            categorized_jobs[source.to_sym][search_term.to_sym] = {
                read_jobs: read_postings,
                unread_jobs: unread_postings
            }
          end # end search_terms.each
        end # end job_sources.each

        erb :jobs_by_date, locals: {
          date: date,
          categorized_jobs: categorized_jobs
        }
      end

      post '/job/:id/:trigger' do |id, trigger|
        job = Job.find(id)
        # mark the post as forget and dont show this posting down the line
        if trigger == 'forget'
          job.update_attribute(:hide, true)
          flash[:info] = "Post marked as #{trigger} (#{job.title}). It won't be displayed the next time."
        elsif trigger == 'read'
          job.update_attribute(:read, true)
          flash[:info] = "Post marked as read (#{job.title})"
        else
          job.add_to_set(:trigger, trigger.upcase)
          job.update_attribute(:read, true) # also mark the job as read
          flash[:info] = "Post marked as #{trigger} (#{job.title})"
        end
        redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
      end

      get '/job/:id' do |id|
        protected!

        job = Job.find(id)
        consultant_emails = Consultant.asc(:first_name).all.pluck(:email)
        resumes = {}
        consultant_emails.each do |email|
          resumes[email] = Consultant.find(email).resumes
        end
        erb :job_by_id, locals: {
          job: job,
          consultants: consultant_emails, # for sending emails
          resumes: resumes,
          tracking: job.applications
        }
      end

      # Send consultant email reg job details
      post '/jobs/forward/:email/:job_id' do |email, job_id|
        job = Job.find(job_id)
        notes = params[:notes]

        # mark the job posting as read
        job.update_attribute(:read, true)

        Delayed::Job.enqueue(
          EmailJobPosting.new(@settings, @user.name, job, Consultant.find_by(email: email), notes),
          queue: 'consultant_emails',
          priority: 5,
          run_at: 5.seconds.from_now
        )

        flash[:info] = "Post marked as 'sent to consultant' & 'read' (#{job.title})"
        redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
      end

      post '/jobs/remind/:email' do |email|
        job_url = params[:job_url]
        job = Job.find_by(url: job_url)

        Delayed::Job.enqueue(
            EmailJobPostingRemainder.new(@settings, @user.name, job, email),
            queue: 'consultant_emails',
            priority: 5,
            run_at: 10.seconds.from_now
        )

        flash[:info] = "Sent reminder to consultant email: #{email}"
      end

      post '/jobs/apply_now/:id' do |job_id|
        vendor_email = params[:vendor_email]
        email_body = params[:email_body]
        resume_name = params[:resume_name]
        email = params[:consultant_email]
        # Add consultant to list of 'applications' in the 'consultant' document to keep track of
        job = Job.find(job_id)
        user = Consultant.find_by(email: email)
        user.applications.find_or_create_by(job_url: job.url) do |application|
          # application.add_to_set(:job_id)
          application.add_to_set(:comments, 'Applied/Forwarded to vendor')
          application.add_to_set(:status, 'APPLIED')
        end
        # Retrieve the resume from mongo
        resume_id = Resume.find_by(resume_name: resume_name).id
        resume = download_resume(resume_id)
        Pony.mail(
            :from => @settings[:email].split('@').first + "<" + @settings[:email] + ">",
            :to => vendor_email,
            :cc => @settings[:cc],
            :subject => "Applying Job Post: (#{job.title})",
            :body => email_body,
            :attachments => {
                "#{email.split('@').first.upcase}.docx" => resume.read
            },
            :via => :smtp,
            :via_options => {
                :address              => @settings[:smtp_address],
                :port                 => @settings[:smtp_port],
                :enable_starttls_auto => true,
                :user_name            => @settings[:email],
                :password             => @settings[:password],
                :authentication       => :plain,
                :domain               => 'localhost.localdomain'
            }
        )
        # add trigger
        job.add_to_set(:trigger, 'SEND_CONSULTANT')
        job.update_attribute(:read, true) # also mark the job as read
        flash[:info] = "Post marked as 'applied' & 'read' (#{job.title})"
        redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
      end

      # Update consultant application details
      # /consultant/:id/application/update
      post '/jobs/consultant/:id/application/update' do |id|
        consultant_id   = id
        application_id  = params[:pk]
        update_key      = params[:name]
        update_value    = params[:value]
        success         = true
        message         = "Successfully updated #{update_key} to #{update_value}"
        consultant = Consultant.find_by(email: consultant_id)
        if consultant.nil?
          success = false
          message = "Cannot find user specified by #{consultant_id}"
        end
        application = consultant.applications.find_by(id: application_id)
        if application.nil?
          success = false
          message = "Cannot find application specified by #{application_id} for user #{consultant_id}"
        end
        begin
          case update_key
            when 'Comments'
              application.add_to_set(update_key.to_sym, update_value)
            else
              application.update_attribute(update_key.to_sym, update_value)
          end
        rescue
          success = false
          message = "Failed to update(#{update_key})"
        end
        { success: success, msg: message }.to_json
      end

      # /application/status/possible_values
      get '/jobs/application/status/possible_values' do
        status_values = []
        %w(APPLIED CHECKING AWAITING_UPDATE_FROM_USER AWAITING_UPDATE_FROM_VENDOR
    FOLLOW_UP INTERVIEW_SCHEDULED REJECTED_BY_VENDOR REJECTED_BY_CLIENT).each do |status|
          status_values << { value: status, text: status }
        end
        if request.xhr?
          halt 200, status_values.to_json
        else
          status_values.to_json
        end
      end

      # /application/closing_status/possible_values
      get '/jobs/application/closing_status/possible_values' do
        status_values = []
        %w(BILLING_RATE_NOT_NEGOTIATED UNDER_QUALIFIED INTERVIEW_FAILED APPROVED).each do |status|
          status_values << { value: status, text: status }
        end
        if request.xhr?
          halt 200, status_values.to_json
        else
          status_values.to_json
        end
      end

      # /application/:id
      delete '/jobs/application/:id' do |id|
        Application.find(id).update_attribute(:hide, true)
        if request.xhr?
          halt 200
        else
          'OK'
        end
      end

      # /upload/resume/:email
      post '/jobs/resume/upload/:email' do |email|
        consultant = Consultant.find_by(email: email)
        s_files = []
        w_files = []

        params[:resumes].each do |resume|
          file_name = email.split('@').first.upcase + '_' + resume[:filename]
          temp_file = resume[:tempfile]
          resume_id = upload_file(temp_file,file_name)
          if resume_id
            consultant.resumes.find_or_create_by(file_name: file_name) do |_resume|
              _resume.id = resume_id
              _resume.resume_name = file_name
              _resume.uploaded_date = DateTime.now
            end
            s_files << file_name
          else
            w_files << file_name
          end
        end
        flash[:info] = "Successfully uploaded files '#{s_files.join(',')}'" unless s_files.empty?
        flash[:warning] = "Failed uploading resume. Resume(s) with '#{w_files.join(',')}' already exists!." unless w_files.empty?
        redirect back
      end

      # Download the resume by its id
      # /resumes/:id
      get '/jobs/resume/:id' do |id|
        # resume_id = Resume.where(:id => id).first
        resume = download_file(id)
        response.headers['content_type'] = "application/octet-stream"
        attachment(resume.filename)
        response.write(resume.read)
        # send_file(
        #   resume.read,
        #   :type => 'application/octet-stream',
        #   :disposition => 'attachment',
        #   :filename => resume.filename
        # )
      end

      # Get all the resumes associated for a consultant
      # /resumes/all/:id
      get '/jobs/resume/all/:id' do |consultant_id|
        consultant = Consultant.find_by(email: consultant_id)
        resumes = []
        consultant.resumes.each do |resume|
          resumes << {
              value: resume.id,
              text: resume.resume_name
          }
        end
        if request.xhr?
          halt 200, resumes.to_json
        else
          resumes.to_json
        end
      end

      #
      # Consultant routes
      #
      get '/jobs/consultant/:id' do |id|
        self_protected!(id)

        consultant = Consultant.find_by(email: id)
        job_applications = []
        consultant.applications.each do |application|
          job = Job.find_by(url: application.job_url)
          _resume = Resume.find_by(_id: application.resume_id)
          resume_name = if _resume
                          _resume.resume_name
                        else
                          ''
                        end
          # Only show applications that aren't hidden
          unless application.hide
            job_applications << {
                job_url: job.url,
                job_id: job.id,
                vendor: job.company,
                title: job.title,
                posted_date: job.date_posted.strftime('%Y-%m-%d'),
                application_id: application.id,
                status: application.status || [],
                closing_status: application.closing_status || [], # for admin only
                comments: application.comments,
                resume_used: application.resume_id, # Only if application.status == 'APPLIED'
                resume_name: resume_name, # associated with the application
                notes: application.notes
            }
          end
        end
        puts job_applications
        erb :consultant_jobs, locals: {
            consultant: consultant,
            # sort job applications by posted_date in desc order and then by job's title in asc order
            job_applications: job_applications.sort{|a, b| [b[:posted_date], a[:title]] <=> [a[:posted_date], b[:title]]},
            admin_user: @user.administrator?
        }
      end
    end
  end
end