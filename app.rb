require 'rubygems'
require 'sinatra'
require 'sinatra/base'
require 'sinatra/flash'
require 'mongo' # Req for GRIDFS
require 'mongoid'
require 'json'
require 'date'
require 'pony'

require_relative 'models/sessions'
require_relative 'models/users'
require_relative 'models/consultants'
require_relative 'models/resumes'
require_relative 'models/fetcher'
require_relative 'core/process_dice'
require_relative 'core/settings'
require_relative 'models/consultant'
require_relative 'models/application'
require_relative 'models/resume'

#
# Monkey Patch Sinatra flash to bootstrap alert
#
module Sinatra
  module Flash
    module Style
      def styled_flash(key=:flash)
        return '' if flash(key).empty?
        id = (key == :flash ? "flash" : "flash_#{key}")
        close = '<a class="close" data-dismiss="alert" href="#">×</a>'
        messages = flash(key).collect do |message|
          "  <div class='alert alert-#{message[0]}'>#{close}\n #{message[1]}</div>\n"
        end
        "<div id='#{id}'>\n" + messages.join + "</div>"
      end
    end
  end
end

class JobPortal < Sinatra::Base
  #
  # Pre-configure sinatra
  #

  configure do
    Mongoid.load!("./mongoid.yml", :development)
    enable :logging, :dump_errors
    enable :sessions
    register Sinatra::Flash
    set :raise_errors, true
  end

  #
  # => BEFORE CLAUSE (runs before every route being processed)
  #

  before do
    # Models
    @users        = UserDAO
    @sessions     = SessionDAO
    # Session Timeout
    @@expiration_date = Time.now + (60 * 2)
    # user browser cookies
    cookie = request.cookies['user_session'] || nil
    @username   = begin
                    Session.find_by(_id: cookie).username
                  rescue Mongoid::Errors::DocumentNotFound
                    nil
                  end
    @admin_user = if @username
                    begin
                      User.find_by(_id: @username).admin
                    rescue Mongoid::Errors::DocumentNotFound
                      false
                    end
                  end
    # Load email information
    Settings.load!("conf/emails.yaml")
  end

  #
  # => ROOT
  #

  get '/' do
    # for logged in users show follow up jobs and applied jobs of 10 each
    consultant = begin
                  Consultant.find_by(email: @username).id
                 rescue Mongoid::Errors::DocumentNotFound
                   ''
                 end
    if @username
      if @admin_user
        jobs_to_render = []
        jobs_to_render_interviews = []
        follow_up_jobs = Application.where(:status.in => ['FOLLOW_UP', 'APPLIED']).select {|a| a.hide == false }
        follow_up_jobs && follow_up_jobs.each do |application|
          jobs_to_render << Job.where(url: application.job_url, hide: false)
        end
        interviews_scheduled = Application.where(:status.in => ['INTERVIEW_SCHEDULED']).select {|a| a.hide == false }
        interviews_scheduled && interviews_scheduled.each do |application|
          jobs_to_render_interviews << Job.where(url: application.job_url, hide: false)
        end
        # remove empty records
        jobs_to_render.map!{ |job| job.entries }.reject(&:empty?)
        jobs_to_render_interviews.map!{ |job| job.entries }.reject(&:empty?)

        # jobs_to_render
        jobs = jobs_to_render.flatten.uniq {|e| e[:url] }
        jobs_interview = jobs_to_render_interviews.flatten.uniq {|e| e[:url]}

        # list of users tracking a job
        tracking_applied = {}
        tracking_interview = {}
        jobs.each do |job|
          job_url = Job.find(job.id).url
          Application.where(job_url: job_url).entries.each do |app|
            consultant = Consultant.find_by(email: app.consultant_id)
            (tracking_applied[job_url] ||= []) << consultant.first_name[0..0].capitalize + consultant.last_name[0..0].capitalize
          end
        end
        jobs_interview.each do |job|
          job_url = Job.find(job.id).url
          Application.where(job_url: job_url).select{|a| a.hide == true}.entries.each do |app|
            consultant = Consultant.find_by(email: app.consultant_id)
            (tracking_interview[job_url] ||= []) << consultant.first_name[0..0].capitalize + consultant.last_name[0..0].capitalize
          end
        end

        erb :index,
            :locals => {
              # Only send the unique jobs by url
              :jobs => jobs,
              :jobs_interview => jobs_interview,
              :tracking_applied => tracking_applied,
              :tracking_interview => tracking_interview
            }
      elsif @username == consultant
        redirect "/consultant/view/#{@username}"
      else
        erb :admin_access_req
      end
    else
      erb :index
    end
  end

  not_found do
    status 404
    erb :not_found
  end

  error do
    error_msg = request.env['sinatra.error']
    erb :error, :locals => { error_msg: error_msg }
  end

  #
  # => USERS AND SESSIONS
  #

  get '/login' do
    if @username
      redirect back
    else
      erb :login, :locals => {:login_error => ''}
    end
  end

  post '/login' do
    username = params[:username]
    password = params[:password]
    # puts "user submitted '#{username}' with pass: '#{password}'"
    user_record = @users.validate_login(username, password)

    if user_record
      # puts "Starting a session for user: #{user_record.email}"
      session_id = @sessions.start_session(user_record.email)
      redirect '/internal_error' unless session_id
      response.set_cookie(
          'user_session',
          :value => session_id,
          # :expires => @@expiration_date,
          :path => '/'
        )
      redirect '/'
    else
      erb :login, :locals => {:login_error => 'Invalid Login'}
    end
  end

  get '/internal_error' do
    "Error: System has encounterd a DB error"
  end

  get '/post_not_found' do
    "Error: Sorry, post not found"
  end

  get '/logout' do
    cookie = request.cookies['user_session']
    @sessions.end_session(cookie)
    session.clear # clear the cookies on user logout
    erb "<div class='alert alert-message'>Logged out</div>"
    redirect '/'
  end

  get '/signup' do
    erb :signup
  end

  post '/signup' do
    username = params[:username]
    password = params[:password]
    verify = params[:verify]
    @errors = {
      'username' => username,
      'username_error' => '',
      'password_error' => '',
      'verify_error' => ''
    }
    if validate_signup(username, password, verify, @errors)
      unless @users.add_user(username, password)
        @errors['username_error'] = 'Username already exists, please choose another'
        return erb :signup # with errors
      end
      session_id = @sessions.start_session(username)
      response.set_cookie(
          'user_session',
          :value => session_id,
          # :expires => @@expiration_date,
          :path => '/'
        )
      redirect '/'
    else
      # puts "user validation failed"
      erb :signup # with errors
    end
  end

  #
  # => CONSULTANTS
  #

  before '/consultants' do
    redirect '/login' if !@username
  end

  # Display consultants available
  get '/consultants' do
    if @admin_user
      erb :consultants, :locals => { :consultants => Consultant.all.entries }
    else
      erb :admin_access_req
    end
  end

  # Add a new consultant
  post '/consultant/new' do
    first_name = params[:FirstName]
    last_name  = params[:LastName]
    email      = params[:Email]
    team       = params[:Team]
    success    = true
    message    = "Successfully added #{email} to team(#{team})"

    if first_name.empty? || last_name.empty? || email.empty?
      success = false
      message = "fields cannot be empty"
    else
      begin
        consultant = Consultant.find_by(email: email)
      rescue Mongoid::Errors::DocumentNotFound
        success = true
        Consultant.create(
          first_name: first_name,
          last_name: last_name,
          email: email,
          team: team
        )
      else
        success = false
        message = "User already exists with email address: #{email}"
      end
    end

    { success: success, msg: message }.to_json
  end

  # Render each consultant individually by email
  get '/consultant/view/:id' do |id|
    if @username == id || @admin_user
      consultant = Consultant.find_by(email: id)
      job_applications = []
      consultant.applications.each do |application|
        job = Job.find_by(url: application.job_url)
        resume_name = begin
                        Resume.find_by(_id: application.resume_id).resume_name
                      rescue Mongoid::Errors::DocumentNotFound
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
            resume_name: resume_name, # assicoated with the application
            notes: application.notes
          }
        end
      end
      erb :consultant,
          :locals => {
            :consultant => consultant,
            :job_applications => job_applications.sort_by{|h| h[:title]},
            :admin_user => @admin_user
          }
    else
      erb :admin_access_req
    end
  end

  # Send consultant email reg job details that he/her has to apply
  post '/consultant/send_posting/:email/:job_id' do |email, job_id|
    job = Job.find(job_id)
    notes = params[:notes]
    # Add consultant to list of 'applications' in the 'consultant' document to keep track of
    user = Consultant.find_by(email: email)
    user.applications.find_or_create_by(job_url: job.url) do |application|
      # application.add_to_set(:job_id)
      application.add_to_set(:comments, 'Forwareded to consultant')
      application.add_to_set(:status, 'AWAITING_UPDATE_FROM_USER')
    end
    # Compose an email to specified consultant
    # p Settings.email
    # p Settings.password
    # p Settings.smtp_address
    # p Settings.smtp_port
    email_body = <<EOBODY
      <p>Hi,</p>
      <p>Check the following link: <a href="#{job.url}">#{job.title}</a> for the job posting.</p>
      <p>Job Details:</p>
      <table width="100%" border="0" cellspacing="0" cellpading="0">
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Title</strong></td>
          <td align="left" width="20%" valign="top">#{job.title}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Location</strong></td>
          <td align="left" width="20%" valign="top">#{job.location}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Posted</strong></td>
          <td align="left" width="20%" valign="top">#{job.date_posted}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Skills</strong></td>
          <td align="left" width="20%" valign="top">#{job.skills}</td>
        <tr>
      </table>
      <br/>
      <p><strong>Notes</strong>: #{notes}</p>
      <p><strong>Important</strong>: <font color="red"> Update your resume as per the job requirement. Try to include all the technologies.</font></p>
      <p>Thanks,<br/>Shiva.</p>
EOBODY
    Pony.mail(
      :from => Settings.email.split('@').first + "<" + Settings.email + ">",
      :to => email,
      :subject => "Apply/Check this job: #{job.title}(#{job.location})",
      :headers => { 'Content-Type' => 'text/html' },
      :body => email_body,
      :via => :smtp,
      :via_options => {
        :address              => Settings.smtp_address,
        :port                 => Settings.smtp_port,
        :enable_starttls_auto => true,
        :user_name            => Settings.email,
        :password             => Settings.password,
        :authentication       => :plain,
        :domain               => 'localhost.localdomain'
      }
    )
    # Same old add trigger
    job.add_to_set(:trigger, 'SEND_CONSULTANT')
    job.update_attribute(:read, true) # also mark the job as read
    flash[:info] = "Post marked as 'sent to consultant' & 'read' (#{job.title})"
    redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
  end

  post '/consultant/send_reminder/:email' do |email|
    job_url = params[:job_url]
    job = Job.find_by(url: job_url)
    email_body = <<EOBODY
      <p>Hi,</p>
      <p>This is a reminder regarding job posting: <a href="#{job.url}">#{job.title}</a> you have been tracking in cloudwick's job portal.</p>
      <p>Follow up with the vendor and let me know the status.</p>
      <p>Job Details:</p>
      <table width="100%" border="0" cellspacing="0" cellpading="0">
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Title</strong></td>
          <td align="left" width="20%" valign="top">#{job.title}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Location</strong></td>
          <td align="left" width="20%" valign="top">#{job.location}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Posted</strong></td>
          <td align="left" width="20%" valign="top">#{job.date_posted}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Skills</strong></td>
          <td align="left" width="20%" valign="top">#{job.skills}</td>
        <tr>
      </table>
      <br/>
      <p><strong>Important</strong>: <font color="red"> Update the status of the posting in the <strong>job_portal</strong>.</font></p>
      <p>Thanks,<br/>Shiva.</p>
EOBODY
    Pony.mail(
      :from => Settings.email.split('@').first + "<" + Settings.email + ">",
      :to => email,
      :subject => "Reminder for job posting: #{job.title}(#{job.location})",
      :headers => { 'Content-Type' => 'text/html' },
      :body => email_body,
      :via => :smtp,
      :via_options => {
        :address              => Settings.smtp_address,
        :port                 => Settings.smtp_port,
        :enable_starttls_auto => true,
        :user_name            => Settings.email,
        :password             => Settings.password,
        :authentication       => :plain,
        :domain               => 'localhost.localdomain'
      }
    )
    flash[:info] = "Sent reminder to constultant email: #{email}"
  end

  # Delete the consultant and all the applications associated to that email
  post '/consultant/delete/:email' do |email|
    Consultant.find_by(email: email).delete
    Application.delete_all(consultant_id: email)
    flash[:info] = "Deleted user('#{email}') and assigned posts"
    redirect "/consultants"
  end

  # Update consultant detail
  post '/consultant/update' do
    consultant_id = params[:pk]
    update_key    = params[:name]
    update_value  = params[:value]
    success       = true
    message       = "Successfully updated #{update_key} to #{update_value}"
    # Find the consultant by id
    consultant = Consultant.find_by(email: consultant_id)
    if consultant.nil?
      success = false
      message = "Cannot find user specified by #{consultant_id}"
    end
    # Update the consultant parameters
    begin
      consultant.update_attribute(update_key.to_sym, update_value)
    rescue
      success = false
      message = "Failed to update(#{update_key})"
    end
    # Return json response to be validated on the client side
    { success: success, msg: message }.to_json
  end

  # Update consultant application details
  post '/consultant/:id/application/update' do |id|
    consultant_id   = id
    application_id  = params[:pk]
    update_key      = params[:name]
    update_value    = params[:value]
    success         = true
    message         = "Sucessfully updated #{update_key} to #{update_value}"
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

  get '/consultant/teams' do
    teams = []
    Consultant.distinct(:team).each do |team|
      teams << {value: team, text: team}
    end
    if request.xhr? # if this is a ajax request
      halt 200, teams.to_json
    else
      teams.to_json
    end
  end

  ###
  ### => APPLICATIONS
  ###

  get '/application/status/possible_values' do
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

  get '/application/closing_status/possible_values' do
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

  delete '/application/:id' do |id|
    Application.find(id).update_attribute(:hide, true)
    if request.xhr?
      halt 200
    else
      'OK'
    end
  end

  ###
  ### => Apply
  ###

  post '/posting/apply_now/:id' do |job_id|
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
    # Compose an email to specified consultant
    Pony.mail(
      :from => Settings.email.split('@').first + "<" + Settings.email + ">",
      :to => vendor_email,
      :subject => "Applying Job Post: (#{job.title})",
      :body => email_body,
      :attachments => {
        "#{email.split('@').first.upcase}.docx" => resume.read
      },
      :via => :smtp,
      :via_options => {
        :address              => Settings.smtp_address,
        :port                 => Settings.smtp_port,
        :enable_starttls_auto => true,
        :user_name            => Settings.email,
        :password             => Settings.password,
        :authentication       => :plain,
        :domain               => 'localhost.localdomain'
      }
    )
    # Same old add trigger
    job.add_to_set(:trigger, 'SEND_CONSULTANT')
    job.update_attribute(:read, true) # also mark the job as read
    flash[:info] = "Post marked as 'applied' & 'read' (#{job.title})"
    redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
  end

  ###
  ### => Resumes
  ###

  post '/upload/resume/:email' do |email|
    consultant = Consultant.find_by(email: email)
    file_name = email.split('@').first.upcase + '_' + params[:file][:filename]
    temp_file = params[:file][:tempfile]
    resume_id = upload_resume(temp_file,file_name)
    if resume_id
      consultant.resumes.find_or_create_by(file_name: file_name) do |resume|
        resume.id = resume_id
        resume.resume_name = file_name
        resume.uploaded_date = DateTime.now
      end
      flash[:info] = "Uploaded sucessfully #{resume_id}"
    else
      flash[:warning] = "Failed uploading resume. Resume with #{file_name} already exists!."
    end
    redirect back
  end

  # Download the resume by its id
  get '/resumes/:id' do |id|
    # resume_id = Resume.where(:id => id).first
    resume = download_resume(id)
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
  get '/resumes/all/:id' do |consultant_id|
    consultant = Consultant.find_by(email: consultant_id)
    resumes = []
    consultant.resumes.each do |resume|
      resumes << {
        id: resume.id,
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
  # => JOBS
  #

  before '/jobs' do
    redirect '/login' if !@username
  end

  get '/jobs' do
    if @admin_user
      jobs = {}
      Job.distinct(:search_term).sort.each do |search_term|
        jobs[search_term] = []
        Job.where(:search_term => search_term).distinct(:date_posted).sort.reverse[0..6].each do |date|
          total_jobs = Job.where(:search_term => search_term, date_posted: date, hide: false).count
          read_jobs  = Job.where(:search_term => search_term, date_posted: date, read: true, hide: false).count
          unread_jobs = total_jobs - read_jobs
          imp_postings = []
          Job.where(:search_term => search_term, date_posted: date, hide: false).each do |job|
            Application.where(job_url: Job.find(job.id).url).entries.each do |app|
              if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
                imp_postings << job
              end
            end
          end
          jobs[search_term] << {
            date_url: date.strftime('%Y-%m-%d'),
            date:     date.strftime('%A, %b %d'),
            count:    total_jobs,
            read:     read_jobs,
            unread:   unread_jobs,
            followup: imp_postings.count
          }
        end
      end
      erb :jobs, :locals => { :jobs => jobs, :fetcher => Fetcher.last }
    else
      erb :admin_access_req
    end
  end

  # Process and show the jobs for a given date
  get '/jobs/:date' do |date|
    if @admin_user
      categorized_jobs = {}
      p2_search_params = %w(bigdata big-data nosql hbase hive pig storm kafka hadoop cassandra)
      Job.distinct(:search_term).sort.each do |search_term|
        read_jobs = Job.where(:search_term => search_term, date_posted: date, read: true, hide: false)
        unread_jobs = Job.where(:search_term => search_term, date_posted: date, read: false, hide: false)
        # seperate postings that are read from unread
        read_postings = []
        read_jobs.each do |job|
          read_postings << job
        end
        unread_postings = []
        unread_jobs.each do |job|
          unread_postings << job
        end
        p1 = Regexp.new(search_term)
        p2 = Regexp.new((p2_search_params - [search_term]).join('|'))
        # sort un-read jobs by priority, p1 postings are which directly have hadoop
        # in title, and p2 postings are which have some realted big-date keyword in
        # title
        unread_p1_jobs = unread_postings.find_all { |post| p1.match(post.title.downcase) }
        unread_p2_jobs = unread_postings.find_all { |post| p2.match(post.title.downcase) }
        unread_lp_jobs  = unread_postings - ( unread_p1_jobs + unread_p2_jobs )
        unread_jobs_sorted = unread_p1_jobs + unread_p2_jobs + unread_lp_jobs

        # Sort read jobs based on follow-up and applied priority
        # gather postings that require attention which are basically are the
        # applications which are marked as follow_up or applied
        postings_req_attention = []
        Job.where(:search_term => search_term, date_posted: date, hide: false).each do |job|
          Application.where(job_url: Job.find(job.id).url).entries.each do |app|
            if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
              postings_req_attention << job
            end
          end
        end
        rest_jobs = read_postings - postings_req_attention
        read_jobs_sorted = postings_req_attention + rest_jobs

        categorized_jobs[search_term] = {
          read_jobs:      read_jobs_sorted,
          unread_jobs:    unread_jobs_sorted,
          atten_req_jobs: postings_req_attention
        }
      end

      # list of users tracking a job
      tracking = {}
      categorized_jobs.each do |search_term, categorized|
        categorized.each do |job_category, jobs|
          jobs.each do |job|
            job_url = Job.find(job.id).url
            Application.where(job_url: job_url).entries.each do |app|
              consultant = Consultant.find_by(email: app.consultant_id)
              (tracking[job_url] ||= []) << consultant.first_name[0..0].capitalize + consultant.last_name[0..0].capitalize
            end
          end
        end
      end

      # sort categories if it has hadoop in it
      sorted_categories = []
      sorted_categories << 'hadoop' if categorized_jobs.keys.include?('hadoop')
      tmp_categories = categorized_jobs.keys - sorted_categories
      sorted_categories = sorted_categories + tmp_categories

      # finally render the page
      erb :jobs_by_date,
          :locals => {
            :date => date,
            :categorized_jobs => categorized_jobs,
            :sorted_categories => sorted_categories,
            :tracking => tracking
          }
    else
      erb :admin_access_req
    end
  end

  get '/job/:id' do |id|
    job = Job.find(id)
    consultant_emails = Consultant.all.pluck(:email)
    resumes = {}
    # { email => { Resumes } }
    consultant_emails.each do |email|
      resumes[email] = Consultant.find(email).resumes
    end
    erb :job_by_id,
        :locals =>
        {
          :job         => Job.find(id),
          :consultants => Consultant.all.pluck(:email), # for sending emails
          :resumes     => resumes,
          :tracking    => Application.where(job_url: job.url)
        }
  end

  # Mark a post as read
  post '/job/:id/read' do |id|
    job = Job.find(id)
    job.update_attribute(:read, true)
    flash[:info] = "Post marked as read (#{job.title})"
    redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
  end

  # Mark the jobs as to trigger later
  post '/job/:id/:trigger' do |id, trigger|
    job = Job.find(id)
    # mark the post as forget and dont show this posting down the line
    if trigger == 'forget'
      job.update_attribute(:hide, true)
      flash[:info] = "Post marked as #{trigger}(#{job.title}). It won't be displayed the next time."
    else
      job.add_to_set(:trigger, trigger.upcase)
      job.update_attribute(:read, true) # also mark the job as read
      flash[:info] = "Post marked as #{trigger}(#{job.title})"
    end
    redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
  end

  # TODO: Manually create job postings by the user
  post '/job/:id' do |id|
  end

  #
  # => FETCHER
  #

  # Initalize a new fetcher to get the jobs in real-time
  get '/fetcher/fetch_now' do
    # get if there any previous jobs running
    fetcher = Fetcher.last
    if ( fetcher && fetcher.job_status != 'running' ) || fetcher.nil?
      p "Initalizing a new fetcher"
      Fetcher.create(
        job_status:             'running',
        progress:               5.0,
        jobs_fetched:           0,
        message:                'Initializing',
        jobs_processed:         0,
        total_jobs_to_process:  0,
        init_time:              DateTime.now
      )
      traverse_depth = 1
      search_terms = Job.distinct(:search_term).sort
      if search_terms.empty?
        search_terms = %w(hadoop cassandra)
      end
      @job_processors = []
      total_postings_maximum = 0 # aggregated for all job processors
      total_postings_required = ( traverse_depth * 50 ) * search_terms.length
      # Gather all the processors
      search_terms.each do |search_term|
        @job_processors << ProcessDicePostings.new(search_term, 1, ['CON_CORP'])
      end
      @job_processors.each do |processor|
        total_postings_maximum += processor.total_postings
      end
      total_iterations_required = if total_postings_required > total_postings_maximum
                                    total_postings_maximum
                                  else
                                    total_postings_required
                                  end
      percentage_for_url_processing = 5
      percentage_per_iteration = ( 90.to_f / total_iterations_required )

      @jobs_to_process = []
      child_pid = Process.fork do
        Fetcher.last.update_attribute(:message, 'Gathering URLs to process')
        begin
          @job_processors.each do |processor|
            traverse_depth.times do |page|
              p "Processing urls for page: #{page + 1}"
              processor.get_urls(page).each do |job_posting|
                @jobs_to_process << job_posting
              end
            end
          end
        rescue Exception => ex
          Fetcher.last.update_attribute(:message, ex)
          Fetcher.last.update_attribute(:job_status, 'failed')
          Process.exit
        end
        Fetcher.last.inc(:total_jobs_to_process, @jobs_to_process.length)
        Fetcher.last.inc(:progress, percentage_for_url_processing)
        Fetcher.last.update_attribute(:message, 'Processing URLs')
        begin
          @jobs_to_process.each do |job|
            @job_processors.first.process_job_postings(job)
            Fetcher.last.inc(:progress, percentage_per_iteration)
            Fetcher.last.inc(:jobs_processed, 1)
          end
        rescue Exception => ex
          Fetcher.last.update_attribute(:message, ex)
          Fetcher.last.update_attribute(:job_status, 'failed')
          Process.exit
        end
        Fetcher.last.update_attribute(:message, 'completed with no errors')
        Fetcher.last.update_attribute(:job_status, 'completed')
        Process.exit
      end
      Process.detach child_pid
    else
      p "Tapping to the existing fetcher"
    end
    erb :fetch_now
  end

  get '/fetcher/fetch_now/progress' do
    # returns how much progress has been made so far
    stat = Fetcher.last
    progress = stat[:progress]
    state = stat[:job_status]
    message = stat[:message]
    processed = stat[:jobs_processed]
    total_jobs_to_process = stat[:total_jobs_to_process]
    if request.xhr? # if this is a ajax request
      halt 200, {progress: progress, state: state, message: message, processed: processed, total_jobs: total_jobs_to_process}.to_json
    else
      "#{progress}, #{state}, #{message}, #{processed}, #{total_jobs_to_process}"
    end
  end

  #
  # => HELPERS
  #

  # Upload's a new resume using GridFS and returns id of the document
  # Onlt creates a document if there is no file exists with the same name
  def upload_resume(file_path, file_name)
    db = nil
    file_id = nil
    begin
      db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
      grid = Mongo::Grid.new(db)

      # Check if a file already exists with the name specified
      files_db = db['fs.files']
      unless files_db.find_one({:filename => file_name})
        return grid.put(
          File.open(file_path),
          filename: file_name,
          # content_type: file_type,
          # metadata: { 'description' => description }
        )
      else
        # p 'File already exists'
        return nil
      end
    rescue
      return nil
    ensure
      db.connection.close if !db.nil?
    end
  end

  # returns a grid fs object
  def download_resume(resume_id)
    db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
    grid = Mongo::Grid.new(db)

    # Get the file out the db
    return grid.get(BSON::ObjectId(resume_id))
    # return grid.get(resume_id)
  rescue Exception => ex
    p ex
    return nil
  ensure
    db.connection.close if !db.nil?
  end

  # Validates user signup
  def validate_signup(email, password, verify, errors)
    email_re = /^[\S]+@[\S]+\.[\S]+$/
    pass_re = /^.{3,20}$/
    if ! email_re.match(email)
      errors['email_error'] = "invalid email address"
      return false
    end
    if ! pass_re.match(password)
      errors['password_error'] = "invalid password."
      return false
    end
    if password != verify
      errors['verify_error'] = "password must match"
      return false
    end
    return true
  end
end
