require 'sinatra/base'
require 'sinatra/flash'
require 'newrelic_rpm'
require 'mongo'
require 'mongoid'
require 'mongoid_search'
require 'json'
require 'date'
require 'pony'
require 'awesome_print'
require 'rest-client'
require 'csv'
require 'logger'
require 'delayed_job'
require 'delayed_job_mongoid'
require 'cgi'
require 'mini_magick'
require 'erb'
require 'ostruct'
require 'tempfile'
require 'fileutils'
require 'net/http'
require 'twilio-ruby'
require 'omniauth'
require 'omniauth-google-oauth2'
require 'fog'
require 'securerandom'
require 'sshkey'
require 'fileutils'

# Load the mongo models
require_relative 'models/application'
require_relative 'models/attachment'
require_relative 'models/attachments'
require_relative 'models/campaign'
require_relative 'models/consultant'
require_relative 'models/consultants'
require_relative 'models/detail'
require_relative 'models/project'
require_relative 'models/usecase'
require_relative 'models/requirement'
require_relative 'models/cluster_configuration'
require_relative 'models/illustration'
require_relative 'models/project_document'
require_relative 'models/email'
require_relative 'models/fetcher'
require_relative 'models/job'
require_relative 'models/resume'
require_relative 'models/resumes'
require_relative 'models/session'
require_relative 'models/sessions'
require_relative 'models/template'
require_relative 'models/user'
require_relative 'models/users'
require_relative 'models/vendor'
require_relative 'models/customer'
require_relative 'models/tracking'
require_relative 'models/document_template'
require_relative 'models/document_signature'
require_relative 'models/document_layout'
require_relative 'models/document_request'
require_relative 'models/cloud_image'
require_relative 'models/cloud_request'
require_relative 'models/cloud_instance'
require_relative 'models/cloud_flavor'
require_relative 'models/training_topic'
require_relative 'models/training_sub_topic'
require_relative 'models/content_slide'
require_relative 'models/content_thumbnail'
require_relative 'models/pdf_file'

# Load core stuff
require_relative 'lib/process_dice'
require_relative 'lib/settings'
require_relative 'lib/vendor_campaign'
require_relative 'lib/customer_campaign'

# Delyed job handlers
require_relative 'lib/dj/simple_task'
require_relative 'lib/dj/custom_task'
require_relative 'lib/dj/campaign_mail'
require_relative 'lib/dj/email_job_posting'
require_relative 'lib/dj/email_job_posting_remainder'
require_relative 'lib/dj/generate_document'
require_relative 'lib/dj/email_request_status'
require_relative 'lib/dj/email_document_request'
require_relative 'lib/dj/email_project_notification'
require_relative 'lib/dj/create_cloud_instances'
require_relative 'lib/dj/delete_cloud_instances'
require_relative 'lib/dj/convert_to_pdf'

# Prawn PDF Generators
require_relative 'lib/prawn/leave_letter'
require_relative 'lib/prawn/offer_letter'
require_relative 'lib/prawn/employment_letter'
require_relative 'lib/prawn/project_document'

#
# Monkey Patch Sinatra flash to bootstrap alert
#
module Sinatra
  module Flash
    # Monkey path Style class
    module Style
      def styled_flash(key = :flash)
        return '' if flash(key).empty?
        id = (key == :flash ? 'flash' : "flash_#{key}")
        close = '<a class="close" data-dismiss="alert" href="#">×</a>'
        messages = flash(key).map do |message|
          "  <div class='alert alert-#{message[0]}'>#{close}\n " \
          "#{message[1]}</div>\n"
        end
        "<div id='#{id}'>\n" + messages.join + '</div>'
      end
    end
  end
end

# This is used by DJ to guess where tmp/pids is located (default)
RAILS_ROOT = File.expand_path('..', __FILE__)
Log = Logger.new(File.expand_path('../log/app.log', __FILE__))
I18n.enforce_available_locales = false
# DelayedJob wants us to be on rails, so it looks for stuff
# in the rails namespace -- so we emulate it a bit
module Rails
  class << self
    attr_accessor :logger

    def root
      RAILS_ROOT
    end
  end
end
Rails.logger = Log

#
# Configure DelayedJob
#
Delayed::Worker.destroy_failed_jobs = false

#
# Main Application logic for handling http routes
#
class Sync < Sinatra::Base
  #
  # Pre-configure sinatra
  #
  ::Logger.class_eval { alias :write :'<<' }
  access_log = ::File.join(
                  ::File.dirname(::File.expand_path(__FILE__)),
                  'log',
                  'access.log'
                )
  access_logger = ::Logger.new(access_log)
  error_logger = ::File.new(
                  ::File.join(
                    ::File.dirname(::File.expand_path(__FILE__)),
                    'log',
                    'error.log'),
                  'a+')
  error_logger.sync = true

  # This code block will run once in any environment
  configure do
    use ::Rack::CommonLogger, access_logger

    # Load mongoid
    Mongoid.load!('config/mongoid.yml', :development)
    # Load settings file
    Settings.load!('config/config.yml')

    enable :logging, :dump_errors
    enable :sessions
    # When it's not set sinatra generates random one on application start and
    # shotgun restarts application before every request.
    set :session_secret, 'super secret' # with out this session's get reset

    register Sinatra::Flash
    set :environment, :production
    # Disable internal middleware for presenting errors as useful HTML pages
    set :show_exceptions, false
    set :raise_errors, false

    # Load OmniAuth
    use OmniAuth::Builder do
      # For additional provider examples please look at 'omni_auth.rb'
      provider :google_oauth2, Settings.google_key, Settings.google_secret, {
        prompt: 'select_account',
        image_aspect_ratio: 'square',
        image_size: 200,
        provider_ignores_state: true
      }
    end
  end

  helpers do
    # define a current_user method, so we can be sure if an user is authenticated
    def current_user
      !session[:uid].nil?
    end

    # check if the user has logged in
    def username
      begin
        Session.find_by(_id: session[:uid]).username
      rescue Mongoid::Errors::DocumentNotFound
        nil
      end
    end

    def user_fullname(user_email)
      begin
        c = Consultant.find_by(email: user_email)
        "#{c.first_name} #{c.last_name}"
      rescue Mongoid::Errors::DocumentNotFound
        nil
      end
    end

    # check if the current user is admin user
    def admin_user
      if username
        begin
          User.find_by(_id: username).admin
        rescue Mongoid::Errors::DocumentNotFound
          false
        end
      end
    end

    def db
      Mongo::MongoClient.new('localhost', 27017).db('job_portal')
    end

    def grid
      Mongo::Grid.new(db)
    end

    def twilio
      Twilio::REST::Client.new(
        @settings[:twilio_account_sid],
        @settings[:twilio_auth_token]
      )
    end
  end

  #
  # => BEFORE CLAUSE (runs before every route being processed)
  #
  before do
    env['rack.errors'] =  error_logger
    @settings   = Settings._settings
    @sessions   = SessionDAO
    @username   = username
    @userfullname = user_fullname(username)
    @admin_user = admin_user
    @admin_name = if @admin_user
                    begin
                      User.find_by(_id: @username)
                        .email
                        .split('@')
                        .first
                        .capitalize
                    rescue Mongoid::Errors::DocumentNotFound
                      'ADMIN'
                    end
                  end

    @doc_requests = DocumentRequest.where(status: 'pending').count

    # we do not want to redirect to twitter when the path info starts
    # with /auth/
    # pass if request.path_info =~ /^\/auth\//
    # pass if request.path_info =~ /\/not_valid_email/

    # /auth/google_oauth2 is captured by omniauth:
    # when the path info matches /auth/google_oauth2, omniauth will redirect to google api
    # unless current_user
    #   ap session[:uid]
    #   ap 'current user not logged in'
    #   redirect to('/auth/google_oauth2')
    # else
    #   ap 'user is already logged in'
    # end
  end

  # after do
  #   # make sure we close any open database connection
  #   @db.connection.close if !@db.nil?
  # end

  not_found do
    status 404
    erb :not_found
  end

  # The error handlers will only be invoked, however, if both the Sinatra
  # :raise_errors and :show_exceptions configuration options have been set to false.
  error do
    error_msg = request.env['sinatra.error']
    erb :error, :locals => { error_msg: error_msg }
  end

  error Moped::Errors::ConnectionFailure do
    error_msg = "Cannot connect to the Mongo. Please notify the admin."
    erb :error, :locals => { error_msg: error_msg }
  end

  #
  # => Routes
  #
  get '/auth/:provider/callback' do
    @auth = env['omniauth.auth']
    if @auth.info['email'].split("@")[1] == "cloudwick.com"
      # signed in as cloudwick user
      # create session for the user
      user_email = @auth.info['email']
      session_uid = @auth['uid']
      google_profile = @auth.info.urls && @auth.info.urls['Google'] || nil

      # make sure user exists in the user collection
      begin
        User.find_by(email: user_email)
      rescue Mongoid::Errors::DocumentNotFound
        User.create(email: user_email)
      end

      # also create/update consultant document
      begin
        Consultant.find_by(email: user_email)
        # .update_attributes(
        #   first_name: @auth.info['first_name'],
        #   last_name: @auth.info['last_name'],
        #   image_url: @auth.info['image'],
        #   google_profile: google_profile
        # )
      rescue Mongoid::Errors::DocumentNotFound
        Consultant.create(
          first_name: @auth.info['first_name'],
          last_name: @auth.info['last_name'],
          email: user_email,
          image_url: @auth.info['image'],
          google_profile: google_profile
        )
      end

      # create a session for the user in the collection
      session_id = @sessions.start_session(user_email, session_uid)
      redirect '/internal_error' unless session_id
      # set the cookie
      session[:uid] = session_uid
      session[:email] = user_email
    else
      halt erb(:login, :locals => {:login_error => 'cloudwick_email'})
    end
    # this is the main endpoint to your application
    redirect to('/')
  end

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
        follow_up_jobs = Application.where(
                           :status.in => %w(FOLLOW_UP APPLIED)
                         ).select { |a| a.hide == false }
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
        redirect "/consultant/#{@username}"
      else
        <<-HTML
        <div class="container theme-showcase" role="main">
          <div class="bs-callout bs-callout-info">
            <p class="lead">You don't have a page yet created by admin. Please contact <a href="mailto:syncadmin@cloudwick.com?subject=Account Creation">
Admin</a> </p>
          </div>
        </div>
        HTML
      end
    else
      erb :index
    end
  end

  get '/up' do
    "Yup!!"
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

  # post '/login' do
  #   username = params[:username]
  #   password = params[:password]
  #   # puts "user submitted '#{username}' with pass: '#{password}'"
  #   user_record = @users.validate_login(username, password)
  #
  #   if user_record
  #     # puts "Starting a session for user: #{user_record.email}"
  #     session_id = @sessions.start_session(user_record.email)
  #     redirect '/internal_error' unless session_id
  #     response.set_cookie(
  #         'user_session',
  #         :value => session_id,
  #         :path => '/'
  #       )
  #     redirect '/'
  #   else
  #     erb :login, :locals => {:login_error => 'Invalid Login'}
  #   end
  # end

  get '/internal_error' do
    "Error: System has encounterd a DB error"
  end

  get '/post_not_found' do
    "Error: Sorry, post not found"
  end

  get '/logout' do
    cookie = session[:uid]
    @sessions.end_session(cookie)
    session.clear # clear the cookies on user logout
    flash[:info] = "You have sucessfully logged out. Thanks for visiting!"
    redirect '/'
  end

  # get '/signup' do
  #   erb :signup
  # end
  #
  # post '/signup' do
  #   username = params[:username]
  #   password = params[:password]
  #   verify = params[:verify]
  #   @errors = {
  #     'username' => username,
  #     'username_error' => '',
  #     'password_error' => '',
  #     'verify_error' => ''
  #   }
  #   if validate_signup(username, password, verify, @errors)
  #     unless @users.add_user(username, password)
  #       @errors['username_error'] = 'Username already exists, please choose another'
  #       return erb :signup # with errors
  #     end
  #     session_id = @sessions.start_session(username)
  #     response.set_cookie(
  #         'user_session',
  #         :value => session_id,
  #         # :expires => @expiration_date,
  #         :path => '/'
  #       )
  #     redirect '/'
  #   else
  #     # puts "user validation failed"
  #     erb :signup # with errors
  #   end
  # end

  #
  # => CONSULTANTS
  #

  before '/consultants' do
    redirect '/login' if !@username
  end

  # Display consultants available
  get '/consultants' do
    if @admin_user
      erb :consultants, :locals => { :consultants => Consultant.asc(:first_name).all.entries }
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
        Consultant.find_by(email: email)
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

  get '/consultant/:username' do |username|
    if @username == username || @admin_user
      erb :consultant_home
    else
      erb :admin_access_req
    end
  end

  # Render each consultant individually by email
  get '/consultant/:id/jobs' do |id|
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
      erb :consultant_jobs,
          :locals => {
            :consultant => consultant,
            # sort job applications by posted_date in desc order and then by job's title in asc order
            :job_applications => job_applications.sort{|a, b| [b[:posted_date], a[:title]] <=> [a[:posted_date], b[:title]]},
            :admin_user => @admin_user
          }
    else
      erb :admin_access_req
    end
  end

  get '/consultant/:id/projects' do |id|
    if @username == id || @admin_user
      erb :consultant_projects,
          locals: {
            consultant: Consultant.find_by(email: id),
            details: Detail.find_or_create_by(consultant_id: id)
          }
    else
      erb :admin_access_req
    end
  end

  get '/consultant/:id/projects/add' do |id|
    erb :consultant_add_project, locals: { consultant: Consultant.find_by(email: id) }
  end

  post '/consultant/:id/projects/add' do |id|
    content_type :text
    success = true
    message = "Sucessfully added project"

    # ap params
    project_name = params[:name]

    consultant = Consultant.find_by(email: id)
    details = Detail.find_by(consultant_id: id)
    begin
      details.projects.find_by(name: project_name)
    rescue Mongoid::Errors::DocumentNotFound
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
          begin
            details.projects.find_by(name: project_name).usecases.find_by(name: params["uc#{usecase_index}name".to_sym])
          rescue Mongoid::Errors::DocumentNotFound
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
          else
            # usecase with the name already exists
            success = false
            message = "Failed to add usecase as the usecase_name: #{usecase_index} already exists for project: #{project_name}"
          end
        end
      end
    else
      # project with same name exists
      success = false
      message = "Failed to add project as the project_name: #{project_name} already exists"
    end

    if success
      Delayed::Job.enqueue(
        EmailProjectNotification.new(@settings, consultant),
        queue: 'project_notifications',
        priority: 10,
        run_at: 10.seconds.from_now
      )
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

  # Send consultant email reg job details that he/her has to apply
  post '/consultant/send_posting/:email/:job_id' do |email, job_id|
    job = Job.find(job_id)
    notes = params[:notes]
    # Add consultant to list of 'applications' in the 'consultant' document to keep track of
    user = Consultant.find_by(email: email)

    # mark the job posting as read
    job.update_attribute(:read, true)

    Delayed::Job.enqueue(
      EmailJobPosting.new(@settings, @admin_name, job, user, notes),
      queue: 'consultant_emails',
      priority: 5,
      run_at: 1.seconds.from_now
    )

    flash[:info] = "Post marked as 'sent to consultant' & 'read' (#{job.title})"
    redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
  end

  post '/consultant/send_reminder/:email' do |email|
    job_url = params[:job_url]
    job = Job.find_by(url: job_url)

    Delayed::Job.enqueue(
      EmailJobPostingRemainder.new(@settings, @admin_name, job, email),
      queue: 'consultant_emails',
      priority: 5,
      run_at: 5.seconds.from_now
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

  post '/consultant/details/update' do
    consultant_id = params[:pk]
    update_key = params[:name]
    update_value = params[:value]
    success = true
    message = "Successfully updated #{update_key} to #{update_value}"

    begin
      # case update_key
      # when 'trainings'
      #   Detail.find_by(consultant_id: consultant_id).add_to_set(update_key.to_sym, update_value)
      # else
        Detail.find_by(consultant_id: consultant_id).update_attribute(update_key.to_sym, update_value)
      # end
    rescue
      success = false
      message = "Failed to update(#{update_key})"
    end
    # Return json response to be validated on the client side
    { success: success, msg: message }.to_json
  end

  get '/deatils/certifications/possible_values' do
    status_values = []
    status_values << { text: 'Cloudera Certified Professional: Data Scientist', value:  'ccpds' }
    status_values << { text: 'Cloudera Certified Developer for Apache Hadoop', value:  'ccdh' }
    status_values << { text: 'Cloudera Certified Administrator for Apache Hadoop', value: 'ccah' }
    status_values << { text: 'Cloudera Certified Specialist in Apache HBase', value: 'ccshb' }
    status_values << { text: 'HortonWorks Certified Apache Hadoop Java Develper', value: 'hcjd' }
    status_values << { text: 'HortonWorks Certified Apache Hadoop Develper', value: 'hchd' }
    status_values << { text: 'HortonWorks Certified Apache Hadoop Admin', value: 'hcha' }
    status_values << { text: 'DataStasx Certified Cassandra 1.2 Developer', value: 'dsccd' }
    status_values << { text: 'MongoDB Certified DBA Associate', value: 'c100dba' }
    status_values << { text: 'MongoDB Certified Developer Associate', value: 'c100dev' }

    if request.xhr?
      halt 200, status_values.to_json
    else
      status_values.to_json
    end
  end

  post '/consultant/:id/details/projects/update' do |consultant_id|
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

  post '/consultant/:id/details/projects/:project_id/usecases/update' do |consultant_id, project_id|
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

  post '/consultant/:id/details/projects/:project_id/usecases/:usecase_id/requirements/update' do |consultant_id, project_id, usecase_id|
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

  post '/consultant/:id/details/projects/:project_id/add_files' do |consultant_id, project_id|
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

  # get '/consultants/teams' do
  #   teams = []
  #   Consultant.distinct(:team).sort.each do |team|
  #     teams << {value: team, text: team}
  #   end
  #   if request.xhr? # if this is a ajax request
  #     halt 200, teams.to_json
  #   else
  #     teams.to_json
  #   end
  # end

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
      :cc => Settings.cc,
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
    s_files = []
    w_files = []

    params[:resumes].each do |resume|
      file_name = email.split('@').first.upcase + '_' + resume[:filename]
      temp_file = resume[:tempfile]
      resume_id = upload_resume(temp_file,file_name)
      if resume_id
        consultant.resumes.find_or_create_by(file_name: file_name) do |resume|
          resume.id = resume_id
          resume.resume_name = file_name
          resume.uploaded_date = DateTime.now
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
      dice_jobs = {}
      indeed_jobs = {}
      internal_jobs = {}

      Job.distinct(:search_term).sort.each do |search_term|
        dice_jobs[search_term] = []
        Job.where(:search_term => search_term, :source => 'DICE').distinct(:date_posted).sort.reverse[0..6].each do |date|
          total_jobs = Job.where(:search_term => search_term, :source => 'DICE', date_posted: date, hide: false).count
          read_jobs  = Job.where(:search_term => search_term, :source => 'DICE', date_posted: date, read: true, hide: false).count
          unread_jobs = total_jobs - read_jobs
          imp_postings = []
          Job.where(:search_term => search_term, :source => 'DICE', date_posted: date, hide: false).each do |job|
            Application.where(job_url: Job.find(job.id).url).entries.each do |app|
              if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
                imp_postings << job
              end
            end
          end
          dice_jobs[search_term] << {
            date_url: date.strftime('%Y-%m-%d'),
            date:     date.strftime('%A, %b %d'),
            count:    total_jobs,
            read:     read_jobs,
            unread:   unread_jobs,
            followup: imp_postings.count
          }
        end

        indeed_jobs[search_term] = []
        Job.where(:search_term => search_term, :source => 'INDEED').distinct(:date_posted).sort.reverse[0..6].each do |date|
          total_jobs = Job.where(:search_term => search_term, :source => 'INDEED', date_posted: date, hide: false).count
          read_jobs  = Job.where(:search_term => search_term, :source => 'INDEED', date_posted: date, read: true, hide: false).count
          unread_jobs = total_jobs - read_jobs
          imp_postings = []
          Job.where(:search_term => search_term, :source => 'INDEED', date_posted: date, hide: false).each do |job|
            Application.where(job_url: Job.find(job.id).url).entries.each do |app|
              if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
                imp_postings << job
              end
            end
          end
          indeed_jobs[search_term] << {
            date_url: date.strftime('%Y-%m-%d'),
            date:     date.strftime('%A, %b %d'),
            count:    total_jobs,
            read:     read_jobs,
            unread:   unread_jobs,
            followup: imp_postings.count
          }
        end

        internal_jobs[search_term] = []
        Job.where(:search_term => search_term, :source => 'INTERNAL').distinct(:date_posted).sort.reverse[0..6].each do |date|
          total_jobs = Job.where(:search_term => search_term, :source => 'INTERNAL', date_posted: date, hide: false).count
          read_jobs  = Job.where(:search_term => search_term, :source => 'INTERNAL', date_posted: date, read: true, hide: false).count
          unread_jobs = total_jobs - read_jobs
          imp_postings = []
          Job.where(:search_term => search_term, :source => 'INTERNAL', date_posted: date, hide: false).each do |job|
            Application.where(job_url: Job.find(job.id).url).entries.each do |app|
              if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
                imp_postings << job
              end
            end
          end
          internal_jobs[search_term] << {
            date_url: date.strftime('%Y-%m-%d'),
            date:     date.strftime('%A, %b %d'),
            count:    total_jobs,
            read:     read_jobs,
            unread:   unread_jobs,
            followup: imp_postings.count
          }
        end
      end

      erb :jobs,
          :locals => {
            :dice_jobs => dice_jobs,
            :indeed_jobs => indeed_jobs,
            :internal_jobs => internal_jobs,
            :fetcher => Fetcher.last
          }
    else
      erb :admin_access_req
    end
  end

  # Process and show the jobs for a given date
  get '/jobs/:date' do |date|
    if @admin_user
      # Create a hash to store read, unread & attention_required jobs
      categorized_jobs = Hash.new { |hash, key| hash[key] = {} }
      tracking = {}
      p2_search_params = %w(bigdata big-data nosql hbase hive pig storm kafka hadoop cassandra)

      %w(DICE INDEED INTERNAL).each do |source|
        Job.distinct(:search_term).sort.each do |search_term|
          read_jobs = Job.where(search_term: search_term, source: source, date_posted: date, read: true, hide: false)
          unread_jobs = Job.where(search_term: search_term, source: source, date_posted: date, read: false, hide: false)

          # seperate postings that are read from unread
          read_postings = []
          read_jobs.each do |job|
            read_postings << job
          end
          unread_postings = []
          unread_jobs.each do |job|
            unread_postings << job
          end
          # priority 1 search terms
          p1 = Regexp.new(search_term)
          # priority 2 search terms
          p2 = Regexp.new((p2_search_params - [search_term]).join('|'))
          # sort un-read jobs by priority, p1 postings are which directly have hadoop
          # in title, and p2 postings are which have a big-date realted keyword in the
          # title
          unread_repeated_jobs = unread_postings.select { |post| Job.where(url: post.url).count > 1 }
          unread_jobs_without_repeated = unread_postings - unread_repeated_jobs # unread less priority jobs
          unread_p1_jobs = unread_jobs_without_repeated.find_all { |post| p1.match(post.title.downcase) }
          unread_p2_jobs = unread_jobs_without_repeated.find_all { |post| p2.match(post.title.downcase) }

          unread_lp_jobs  = unread_jobs_without_repeated - ( unread_p1_jobs + unread_p2_jobs )
          # unread jobs sorted by priority
          unread_jobs_sorted = unread_p1_jobs + unread_p2_jobs + unread_lp_jobs

          # Sort read jobs based on follow-up and applied priority
          # gather postings that require attention which are basically are the
          # job postings which are marked as follow_up or applied
          postings_req_attention = []
          # TODO for now commenting this, figure out a better way to implement this with out complex looping quries
          # Job.where(search_term: search_term, source: source, date_posted: date, hide: false).each do |job|
          #   Application.where(job_url: Job.find(job.id).url).entries.each do |app|
          #     if app.status.include?('FOLLOW_UP') || app.status.include?('APPLIED')
          #       postings_req_attention << job
          #     end
          #   end
          # end
          # rest_jobs = read_postings - postings_req_attention
          # read_jobs_sorted = postings_req_attention + rest_jobs

          categorized_jobs[source][search_term] = {
            # read_jobs:      read_jobs_sorted,
            read_jobs:            read_postings,
            unread_jobs:          unread_jobs_sorted,
            unread_repeated_jobs: unread_repeated_jobs,
            atten_req_jobs:       postings_req_attention
          }
        end
      end

      # list of users tracking a job
      categorized_jobs.each do |source, categorized|
        categorized.each do |search_term, category|
          category.each do |job_category, jobs|
            jobs.each do |job|
              job_url = Job.find(job.id).url
              Application.where(job_url: job_url).entries.each do |app|
                consultant = Consultant.find_by(email: app.consultant_id)
                (tracking[job_url] ||= []) << consultant.first_name[0..0].capitalize + consultant.last_name[0..0].capitalize
              end
            end
          end
        end
      end

      # ap categorized_jobs

      # finally render the page
      erb :jobs_by_date,
          :locals => {
            :date => date,
            :categorized_jobs => categorized_jobs,
            :tracking => tracking
          }
    else
      erb :admin_access_req
    end
  end

  get '/job/:id' do |id|
    job = Job.find(id)
    consultant_emails = Consultant.asc(:first_name).all.pluck(:email)
    resumes = {}
    # { email => { Resumes } }
    consultant_emails.each do |email|
      resumes[email] = Consultant.find(email).resumes
    end
    erb :job_by_id,
        :locals =>
        {
          :job         => Job.find(id),
          :consultants => consultant_emails, # for sending emails
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
      flash[:info] = "Post marked as #{trigger} (#{job.title}). It won't be displayed the next time."
    else
      job.add_to_set(:trigger, trigger.upcase)
      job.update_attribute(:read, true) # also mark the job as read
      flash[:info] = "Post marked as #{trigger} (#{job.title})"
      redirect "/jobs/#{job.date_posted.strftime('%Y-%m-%d')}"
    end
  end

  # Manually create job postings by the user
  post '/job/new' do
    success    = true
    message    = "Successfully added job"

    params.keys.each do |p|
      if params[p].empty?
        success = false
        message = "Required fields are not present"
      end
    end

    if success
      begin
        Job.find_by(url: params[:URL])
      rescue Mongoid::Errors::DocumentNotFound
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
      else
        success = false
        message = "Job already exists with url: #{params[:URL]}"
      end
    end

    { success: success, msg: message }.to_json
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

  # Handles the search queries for job collection
  post '/search' do
    search_term = params[:search]
    results = []

    if search_term.match(/\s/)
      Job.full_text_search(search_term, match: :all).entries.map do |job|
        results << { id: job._id, title: job.title }
      end
    elsif uri?(search_term)
      begin
        job = Job.find_by(url: search_term)
        results << {id: job._id, title: job.title}
      rescue Mongoid::Errors::DocumentNotFound
        # do nothing
      end
    else
      Job.full_text_search(search_term).entries.map do |j|
        results << { id: j._id, title: j.title }
      end
    end

    erb :search, :locals => { :search_term => search_term ,:results => results }
  end

  ###
  ### Vendors
  ###
  before '/vendors' do
    redirect '/login' if !@username
  end

  # Display vendors available
  get '/vendors' do
    if @admin_user
      # coll = Vendor.all.entries
      # curr_page = if params[:page].nil?
      #               1
      #             else
      #               params[:page].to_i
      #             end
      # page_size = 10
      # num_pages = coll.size / page_size
      # batch_end = curr_page * page_size
      # batch_start = curr_page == 1 ? 0 : batch_end - page_size
      # curr_batch = coll[batch_start..batch_end-1]
      # # puts "curr_page: #{curr_page}, num_pages: #{num_pages}, page_size: #{page_size}"
      # erb :vendors,
      #     :locals => {
      #       num_pages: num_pages,
      #       curr_batch: curr_batch,
      #       curr_page: curr_page,
      #       last_page: num_pages,
      #       page_size: page_size
      #     }
      data = []
      Vendor.only(:first_name, :last_name, :company, :phone, :email).each do |v|
        data << [ v.first_name || 'NA', v.last_name || 'NA', v.company || 'NA' , v.phone || 'NA', v.email ]
      end
      erb :vendors, :locals => { vendors_data: data }
    else
      erb :admin_access_req
    end
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
      begin
        Vendor.find_by(email: email)
      rescue Mongoid::Errors::DocumentNotFound
        Vendor.create(
          first_name: first_name,
          last_name: last_name,
          email: email,
          company: company,
          phone: phone
        )
        success = true
      else
        success = false
        message = "Vendor already exists with email address: #{email}"
      end
    end

    { success: success, msg: message }.to_json
  end

  # Parse csv, tsv file and upload them to mongo
  post '/vendors/bulkadd' do
    email_regex = Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')
    parsed_records = 0
    failed_records = 0
    new_records_inserted = 0
    duplicate_records = 0
    csv = CSV.parse(File.read(params[:file][:tempfile]), headers: true)
    csv.each do |vendor|
      if vendor['email']
        if vendor.fetch('email') =~ email_regex
          parsed_records += 1
          begin
            Vendor.find_by(email: vendor.fetch('email'))
            duplicate_records += 1
          rescue Mongoid::Errors::DocumentNotFound
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

  ###
  ### Customers
  ###
  before '/customers' do
    redirect '/login' if !@username
  end

  # Display vendors available
  get '/customers' do
    if @admin_user
      data = []

      Customer.only(:first_name, :last_name, :company, :phone, :industry).each do |c|
        data << [ c.first_name, c.last_name, c.company, c.phone, c.industry || "NA" ]
      end
      erb :customers,
          :locals => {
            customers_data: data
          }
    else
      erb :admin_access_req
    end
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
      begin
        Customer.find_by(email: email)
      rescue Mongoid::Errors::DocumentNotFound
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
      else
        success = false
        message = "Customer already exists with email address: #{email}"
      end
    end

    { success: success, msg: message }.to_json
  end

  # Parse csv, tsv file and upload them to mongo
  post '/customers/bulkadd' do
    email_regex = Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')
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
        if customer.fetch('Email') =~ email_regex
          parsed_records += 1
          begin
            Customer.find_by(email: customer.fetch('Email'))
            duplicate_records += 1
          rescue Mongoid::Errors::DocumentNotFound
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

  ###
  ### Email Campaigning
  ###
  before '/campaign' do
    redirect '/login' if !@username
  end

  get '/campaign' do
    if @admin_user
      Campaign.all.each do |campaign|
        get_campaign_stats(campaign._id)
      end
      erb :campaign,
          :locals => {
            :templates => Template.all,
            :active_campaigns => Campaign.where(active: true).all,
            :all_campaign_stats => get_campaign_sent_events,
            :customer_groups => Customer.distinct(:industry).compact,
            :customer => Customer
          }
    else
      erb :admin_access_req
    end
  end

  get '/campaign/templates' do
    if @admin_user
      erb :templates, :locals => { :templates => Template.all }
    else
      erb :admin_access_req
    end
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
      begin
        Template.find_by(name: template_name)
      rescue Mongoid::Errors::DocumentNotFound # template not found
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
        # Create the actual tempalte
        Template.create(
          name: template_name,
          subject: template_subject,
          content: template_body,
          html: html_only
        )
      else
        success = false
        message = "Template already exists with name: #{template_name}"
      end
    end

    { success: success, msg: message }.to_json
  end

  post '/campaign/email_template/:id/update_content' do |id|
    template_subject = params[:subject]
    template_body = params[:body]
    success    = true
    message    = "Successfully updated email template"

    if template_body.empty? || template_subject.empty?
      success = false
      message = "fields cannot be empty"
    else
      begin
        template = Template.find_by(_id: id)
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
      rescue Mongoid::Errors::DocumentNotFound # template not found
        success = false
        message = "Something went wrong, document not found!!!"
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

    message = VendorCampaign.new(template_name, all_vendors, replied_vendors_only).start

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
    message = "Starting Campaign..."

    message = CustomerCampaign.new(template_name, customer_vertical, replied_customers_only, nodups).start

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
        attachment_id = upload_attachment(attachment_tmp_file, attachment_filename)
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
        attachment_id = upload_attachment(attachment_tmp_file, attachment_filename)
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
        begin
          Vendor.where(email: unsubscriber_email).update(unsubscribed: true)
        rescue Mongoid::Errors::DocumentNotFound
        end
        begin
          Customer.where(email: unsubscriber_email).update(unsubscribed: true)
        rescue Mongoid::Errors::DocumentNotFound
        end
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
        begin
          Vendor.where(email: email).update(bounced: true)
        rescue Mongoid::Errors::DocumentNotFound
        end
        begin
          Customer.where(email: email).update(bounced: true)
        rescue Mongoid::Errors::DocumentNotFound
        end
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

  #
  # => Documents Management
  #
  before '/documents' do
    redirect '/login' if !@username
  end

  get '/documents' do
    if @admin_user
      erb :documents,
          :locals => {
            :templates            => DocumentTemplate.all,
            :signatures           => DocumentSignature.all,
            :layouts              => DocumentLayout.all,
            :pending_requests     => DocumentRequest.where(status: 'pending'),
            :approved_requests    => DocumentRequest.where(status: 'approved'),
            :disapproved_requests => DocumentRequest.where(status: 'disapproved'),
          }
    else
      erb :admin_access_req
    end
  end

  get '/documents/templates' do
    if @admin_user
      # (signature_images ||= []) << DocumentSignature.all.each do |signature|
      #   grid.get(BSON::ObjectId(signature.id)).read
      # end
      erb :doc_templates,
          :locals => {
            :templates  => DocumentTemplate.all,
            :signatures => DocumentSignature.all,
            :layouts    => DocumentLayout.all
          }
    else
      erb :admin_access_req
    end
  end

  post '/documents/templates' do
    puts CGI.unescapeHTML(params["body"])
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
      begin
        DocumentTemplate.find_by(name: template_name)
      rescue Mongoid::Errors::DocumentNotFound # template not found
        success = true
        # Create the actual tempalte
        DocumentTemplate.create(
          name: template_name,
          type: template_type,
          content: template_body,
        )
      else
        success = false
        message = "Template already exists with name: #{template_name}"
      end
    end

    { success: success, msg: message }.to_json
  end

  post '/documents/templates/:id/update_template' do |id|
    template_type = params[:type]
    template_body = params[:body]
    success    = true
    message    = "Successfully updated template"

    if template_body.empty? || template_type.empty?
      success = false
      message = "fields cannot be empty"
    else
      begin
        template = DocumentTemplate.find_by(_id: id)
        template.update_attributes(
          type: template_type,
          content: template_body
        )
      rescue Mongoid::Errors::DocumentNotFound
        success = false
        message = "Something went wrong, document not found!!!"
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
  # this route resoleve to /documents/signatures/id/render
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

  # get '/documents/download/:id' do |file_id|
  #   document = download_file(file_id)
  #   response.headers['content_type'] = "application/octet-stream"
  #   attachment(document.filename)
  #   response.write(document.read)
  # end

  # post '/documents/render/:type' do |document_type|
  #   email_regex = Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')
  #   cname = params[:name]
  #   email = params[:email]
  #   company = params[:company]
  #   position = params[:position]
  #   start_date = params[:sdate]
  #   end_date = params[:edate]
  #   dated = params[:dated]
  #   tname = params[:tname]
  #   sname = params[:sname]
  #   lname = params[:layout]
  #   rid = params[:rid] # open present if this a request from consultant
  #   document_format = ''
  #   namespace = nil

  #   success    = true
  #   message    = "Successfully generated #{document_type}"

  #   begin
  #     signature_id = DocumentSignature.find_by(filename: sname).file_id
  #     layout_id = DocumentLayout.find_by(filename: lname).file_id

  #     tmp_file = Tempfile.new(cname.downcase.gsub(' ', '_'))

  #     case document_type
  #     when 'leaveletter'
  #       if Date.strptime(start_date, "%m/%d/%Y") > Date.strptime(end_date, "%m/%d/%Y")
  #         success = false
  #         message = "start date should be less than end date"
  #       end
  #       document_format = 'LEAVELETTER'
  #       namespace = OpenStruct.new(name: cname, start_date: start_date, end_date: end_date)
  #       # Build an erb template and replace variables
  #       template_content = DocumentTemplate.find_by(name: tname).content
  #       erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
  #       template = ERB.new(erb_template).result(namespace.instance_eval {binding})
  #     when 'offerletter'
  #       document_format = 'OFFERLETTER'
  #       namespace = OpenStruct.new(
  #         name: cname,
  #         start_date: start_date,
  #         position: position,
  #         li: '•'
  #       )
  #       # Build an erb template and replace variables
  #       template_content = DocumentTemplate.find_by(name: tname).content
  #       erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
  #       template = ERB.new(erb_template).result(namespace.instance_eval {binding})
  #     when 'employmentletter'
  #       document_format = 'EMPLOYMENTLETTER'
  #       namespace = OpenStruct.new(name: cname, start_date: start_date, position: position)
  #       # Build an erb template and replace variables
  #       template_content = DocumentTemplate.find_by(name: tname).content
  #       erb_template = template_content.gsub('{{', '<%=').gsub('}}', '%>')
  #       template = ERB.new(erb_template).result(namespace.instance_eval {binding})
  #     end

  #     if email !~ email_regex
  #       success = false
  #       message = "email not formatted properly"
  #     else
  #       case document_type
  #       when 'leaveletter'
  #         LeaveLetter.new(
  #           cname,
  #           company,
  #           grid.get(BSON::ObjectId(signature_id)).read,
  #           grid.get(BSON::ObjectId(layout_id)).read,
  #           Date.strptime(start_date, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           Date.strptime(end_date, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           Date.strptime(dated, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           template,
  #           tmp_file.path
  #         ).build!
  #       when 'offerletter'
  #         OfferLetter.new(
  #           cname,
  #           company,
  #           grid.get(BSON::ObjectId(signature_id)).read,
  #           grid.get(BSON::ObjectId(layout_id)).read,
  #           Date.strptime(start_date, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           Date.strptime(dated, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           template,
  #           tmp_file.path
  #         ).build!
  #       when 'employmentletter'
  #         EmploymentLetter.new(
  #           cname,
  #           company,
  #           grid.get(BSON::ObjectId(signature_id)).read,
  #           grid.get(BSON::ObjectId(layout_id)).read,
  #           Date.strptime(start_date, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           Date.strptime(dated, "%m/%d/%Y").strftime('%B %d, %Y'),
  #           template,
  #           tmp_file.path
  #         ).build!
  #       end
  #       success = true
  #       message = "Sucessfully sent #{document_type} to #{cname}"
  #       file_id = upload_file(tmp_file.path, Pathname.new(tmp_file.path).basename.to_s)
  #       if file_id
  #         redirect "/documents/download/#{file_id}"
  #       else
  #         success = false
  #         message = 'Failed rendering file to mongo'
  #       end
  #     end
  #   rescue ArgumentError
  #     success = false
  #     message = "Cannot parse date format (expected format: mm/dd/yyyy)"
  #   ensure
  #     tmp_file.close
  #   end
  #   { success: success, msg: message }.to_json
  # end

  post '/documents/send/:type' do |document_type|
    email_regex = Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')
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

      if email !~ email_regex
        success = false
        message = "email not formatted properly"
      else
        Delayed::Job.enqueue(
          GenerateDocument.new(email, @settings, document_format, @admin_name,
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
            approved_by: @admin_name,
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
  # TODO replace this with download/preview of documents
  post '/documents/send/:type/admin' do |document_type|
    email_regex = Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')
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

      if email !~ email_regex
        success = false
        message = "email not formatted properly"
      else
        Delayed::Job.enqueue(
          GenerateDocument.new(@username, @settings, document_format, @admin_name,
            grid.get(BSON::ObjectId(signature_id)).read,
            grid.get(BSON::ObjectId(layout_id)).read,
            generate_document_opts
          ),
          queue: 'consultant_document_requests',
          priority: 10,
          run_at: 1.seconds.from_now
        )
        success = true
        message = "Sucessfully sent #{document_type} to #{@username}"
      end
    rescue ArgumentError
      success = false
      message = "Cannot parse date format (expected format: mm/dd/yyyy)"
    end
    { success: success, msg: message }.to_json
  end

  post '/documents/requests/deny/:id' do |rid|
    dr = DocumentRequest.find(rid)
    dr.update_attributes(status: 'disapproved', disapproved_by: @admin_name, disapproved_at: DateTime.now)
    Delayed::Job.enqueue(
      EmailRequestStatus.new(@settings, @admin_name, dr),
      queue: 'consultant_document_requests',
      priority: 10,
      run_at: 1.seconds.from_now
    )
    flash[:info] = 'Sucessfully disapproved and updated the user status of the request'
    redirect "/documents"
  end

  get '/requests/documents' do
    erb :doc_requests, :locals => {:error_msg => ''}
  end

  #
  # => Document Requests (Consultant Routes)
  #

  get '/documents/:userid' do |userid|
    erb :consultant_documents,
        locals: {
          consultant: Consultant.find_by(email: userid),
          pending_requests: DocumentRequest.where(consultant_email: userid, status: 'pending'),
          previous_requests: DocumentRequest.where(consultant_email: userid, :status.ne => 'pending')
        }
  end

  post '/documents/:userid/request' do |userid|
    # ap params
    success    = true
    message    = "Successfully created a requests"

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
      message = "Select an appropriate document type"
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
      # TODO remove this comments once testing is done
      # Delayed::Job.enqueue(
      #   EmailDocumentRequest.new(@settings, @admin_name, dr),
      #   queue: 'consultant_document_requests',
      #   priority: 10,
      #   run_at: 1.seconds.from_now
      # )
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

  #
  # => Timesheets
  #
  get '/timesheets' do
    erb :timesheets
  end

  #
  # => CloudServers
  #

  before '/cloudservers' do
    redirect '/login' if !@username
  end

  get '/cloudservers' do
    if @admin_user
      openstack_capacity = {}

      conn = create_openstack_connection
      if conn
        user_limits = conn.get_limits
        openstack_capacity[:current_instances] = user_limits.body['limits']['absolute']['totalInstancesUsed']
        openstack_capacity[:max_instances]     = user_limits.body['limits']['absolute']['maxTotalInstances']
        openstack_capacity[:max_cores]         = user_limits.body['limits']['absolute']['maxTotalCores']
        openstack_capacity[:current_cores]     = user_limits.body['limits']['absolute']['totalCoresUsed']
        openstack_capacity[:max_ram]           = user_limits.body['limits']['absolute']['maxTotalRAMSize']
        openstack_capacity[:current_ram]       = user_limits.body['limits']['absolute']['totalRAMUsed']
        openstack_capacity[:current_secgroups] = user_limits.body['limits']['absolute']['totalSecurityGroupsUsed']
        openstack_capacity[:max_secgroups]     = user_limits.body['limits']['absolute']['maxSecurityGroups']
      end
      erb :cloudservers, locals: { oc: openstack_capacity }
    else
      erb :admin_access_req
    end
  end

  get '/cloudservers/requests' do
    if @admin_user
      erb :cloudserver_requests,
          locals: {
            consultant: Consultant.find_by(email: @username),
            images: CloudImage.all,
            flavors: CloudFlavor.all,
            pending_requests: CloudRequest.where(approved?: false, disapproved?: false),
            bootstrapping_requests: CloudRequest.where(approved?: true, fulfilled?: false, connection_failed?: false),
            failed_requests: CloudRequest.where(approved?: true, fulfilled?: false, connection_failed?: true),
            running_requests: CloudRequest.where(approved?: true, fulfilled?: true, active?: true)
          }
    else
      erb :admin_access_req
    end
  end

  get '/cloudservers/requests/:userid' do |userid|
    erb :consultant_cloudservers,
        locals: {
          consultant: Consultant.find_by(email: userid),
          images: CloudImage.all,
          flavors: CloudFlavor.all,
          pending_requests: CloudRequest.where(requester: userid, approved?: false, disapproved?: false),
          bootstrapping_requests: CloudRequest.where(requester: userid, approved?: true, fulfilled?: false),
          running_requests: CloudRequest.where(requester: userid, approved?: true, fulfilled?: true, active?: false)
        }
  end

  post '/cloudservers/requests/deny/:id' do |rid|
    dr = CloudRequest.find(rid)
    dr.update_attributes(disapproved?: true, disapproved_by: @admin_name, disapproved_at: DateTime.now)
    # TODO write a delayed job
    # Delayed::Job.enqueue(
    #   EmailRequestStatus.new(@settings, @admin_name, dr),
    #   queue: 'consultant_document_requests',
    #   priority: 10,
    #   run_at: 1.seconds.from_now
    # )
    # Delete all the created requests associated with the user
    dr.cloud_instances.delete_all
    flash[:info] = 'Sucessfully disapproved and updated the user status of the request'
    redirect "/cloudservers/requests"
  end

  post '/cloudservers/requests/approve/:id' do |rid|
    cr = CloudRequest.find(rid)
    cr.update_attributes(approved?: true, approved_by: @admin_name, approved_at: DateTime.now)

    Delayed::Job.enqueue(
      CreateCloudInstances.new(@settings, cr, User.find_by(email: cr.requester)),
      queue: 'create_cloud_servers',
      priority: 10
    )

    flash[:info] = 'Sucessfully approved and scheduled the servers to bootstrap'
    redirect "/cloudservers/requests"
  end

  post '/cloudservers/requests/retry/:id' do |rid|
    cr = CloudRequest.find(rid)
    cr.update_attributes!(connection_failed?: false)

    Delayed::Job.enqueue(
      CreateCloudInstances.new(@settings, cr, User.find_by(email: cr.requester)),
      queue: 'create_cloud_servers',
      priority: 10
    )

    flash[:info] = 'Sucessfully scheduled the servers to bootstrap (retry)'
    redirect "/cloudservers/requests"
  end

  post '/cloudservers/requests/delete/:id' do |rid|
    success = true
    message = "Successfully scheduled instance(s) to be deleted"

    cr = CloudRequest.find(rid)

    Delayed::Job.enqueue(
      DeleteCloudInstances.new(@settings, cr, User.find_by(email: cr.requester)),
      queue: 'delete_cloud_servers',
      priority: 10
    )

    flash[:info] = 'Sucessfully scheduled the servers to delete'

    { success: success, msg: message }.to_json
  end

  post '/cloudservers/:id/requests' do |consultant_id|
    # ap params
    success    = true
    message    = "Successfully created a requests"

    # {"NumberOfInstances"=>"1", "InstanceType"=>"1", "Image"=>"566b97d7-2ee9-4c1a-bc51-c25424215f7f", "DomainName"=>"", "Purpose"=>"", "splat"=>[], "captures"=>["ashrith@cloudwick.com"], "id"=>"ashrith@cloudwick.com"}
    number_of_instances = params[:NumberOfInstances]
    flavor_id = params[:InstanceType]
    image_id = params[:Image]
    server_name = params[:ServerName] || consultant_id.split('@').first.gsub('.', '_')
    domain_name = params[:DomainName] || 'ankus.cloudwick.com'
    purpose = params[:Purpose]

    req = CloudRequest.create(requester: consultant_id, purpose: purpose)
    flavor = CloudFlavor.find(flavor_id)

    number_of_instances.to_i.times do |i|
      os_type = CloudImage.find(image_id).os
      req.cloud_instances << CloudInstance.new(
                              user_id: consultant_id,
                              instance_name: "#{server_name}#{i+1}.#{domain_name}",
                              flavor_id: flavor_id,
                              image_id: image_id,
                              os_flavor: os_type.downcase,
                              vcpus: flavor.vcpus,
                              mem: flavor.mem,
                              disk: flavor.disk
                            )
    end

    # TODO remove comments - enable sending email alerts
    # @settings[:admin_phone].each do |to_phone|
    #   twilio.account.messages.create(
    #     from: @settings[:twilio_phone],
    #     to: to_phone,
    #     body: "SYNC: #{consultant_id} requested #{number_of_instances} servers. Purpose: #{purpose}"
    #   )
    # end

    { success: success, msg: message }.to_json
  end

  get '/cloudservers/request/:id' do |request_id|
    request    = CloudRequest.find(request_id)
    user       = User.find(request.requester)
    # TODO: get the login user based on the image and push that to the login instructions modal
    erb :cloudserver_request_details, locals: { request: request, user: user }
  end

  get '/cloudservers/request/partial/:id' do |request_id|
    erb :cloudserver_request_details_partial, locals: { request: CloudRequest.find(request_id) }
  end

  get '/cloudservers/request/progress/:id' do |request_id|
    # returns how much progress has been made so far on instances
    ff = CloudRequest.find(request_id).fulfilled?
    if request.xhr? # if this is a ajax request
      halt 200, {fulfilled: ff}.to_json
    else
      "#{ff}"
    end
  end

  # cloud instance types
  get '/cloudservers/flavors' do
    erb :cloud_flavors, locals: { flavors: CloudFlavor.all }
  end

  post '/cloudservers/flavors' do
    id = params[:flavorid]
    name = params[:flavorname]
    vcpus = params[:vcpus]
    mem = params[:mem]
    disk = params[:disk]

    success    = true
    message    = "Successfully added cloud flavor details"

    CloudFlavor.find_or_create_by(
      flavor_id: id,
      flavor_name: name,
      vcpus: vcpus,
      mem: mem,
      disk: disk
    )

    flash[:info] = message
    { success: success, msg: message }.to_json
  end

  delete '/cloudservers/flavors/:id' do |id|
    CloudFlavor.find_by(_id: id).delete
  end

  get '/cloudservers/images' do
    erb :cloudimages, locals: { images: CloudImage.all }
  end

  post '/cloudservers/images' do
    imageid = params[:imageid]
    os = params[:os]
    osver = params[:osver]
    osarch = params[:osarch]
    osloginname = params[:osloginname]

    success    = true
    message    = "Successfully added cloud image details"

    CloudImage.find_or_create_by(
      image_id: imageid,
      os: os,
      os_ver: osver,
      os_arch: osarch,
      username: osloginname
    )

    flash[:info] = message
    { success: success, msg: message }.to_json
  end

  delete '/cloudservers/images/:id' do |id|
    CloudImage.find_by(_id: id).delete
  end

  #
  # => Training routes
  #
  before '/training' do
    redirect '/login' if !@username
  end

  get '/training' do
    erb :training, locals: {
      training_topics: TrainingTopic.all
    }
  end

  post '/training/topic/create' do
    topic_name = params[:tname]
    email = params[:email]

    success    = true
    message    = "Successfully added new training topic #{topic_name}"

    TrainingTopic.find_or_create_by(
      name: topic_name.downcase.tr(' ', '_'), # parse the topic to more referrable format
      content_managed_by: email
    )

    flash[:info] = message
    { success: success, msg: message }.to_json
  end

  # TODO deprecate this
  post '/training/topic/delete/:id' do |id|
    topic = TrainingTopic.find(id)
    topic.training_sub_topics.delete_all
    topic.delete
  end

  get '/training/topic/:id' do |id|
    erb :training_topic, locals: {
      topic: TrainingTopic.find(id)
    }
  end

  post '/training/topic/:tid/subtopic/create' do |tid|
    sub_topic_name = params[:tname]
    et_topic = params[:et]

    if et_topic.to_i > 180
      success = false
      message = "It's not recommended to put sub topics greater than 3 hours"
    else
      TrainingTopic.find(tid).training_sub_topics.find_or_create_by(
        name: sub_topic_name.downcase.tr(' ', '_'), # parse the topic to more referrable format
        et: et_topic.to_i
      )
      success    = true
      message    = "Successfully added new training sub topic #{sub_topic_name}"

      flash[:info] = message
    end

    { success: success, msg: message }.to_json
  end

  post '/training/topic/:tid/subtopic/delete/:stid' do |tid, stid|
    sub_topic = TrainingSubTopic.find(stid)
    if sub_topic
      content_slide_files = []
      content_thumbnail_files = []

      if sub_topic.pdf_file.respond_to?(:file_id)
        grid_file = sub_topic.pdf_file.file_id
        grid.delete(BSON::ObjectId(grid_file)) if grid_file
        sub_topic.content_slides.each do |slide|
          content_slide_files << slide.file_id if slide.respond_to?(:file_id)
        end
        unless content_slide_files.empty?
          content_slide_files.each do |slide_file|
            grid.delete(BSON::ObjectId(slide_file)) if slide_file
          end
        end
        sub_topic.content_thumbnails.each do |thumb|
          content_thumbnail_files << thumb.file_id if thumb.respond_to?(:file_id)
        end
        unless content_thumbnail_files.empty?
          content_thumbnail_files.each do |thumb_file|
            grid.delete(BSON::ObjectId(thumb_file)) if thumb_file
          end
        end
        sub_topic.content_slides.delete_all
        sub_topic.content_thumbnails.delete_all
        sub_topic.pdf_file.delete
      end
      sub_topic.delete
    end
  end

  get '/training/topic/:tid/subtopic/:stid' do |tid, stid|
    topic = TrainingTopic.find(tid)
    erb :training_sub_topic, locals: {
      topic: topic,
      sub_topic: topic.training_sub_topics.find(stid)
    }
  end

  post '/training/topic/:tid/subtopic/:stid/upload' do |tid, stid|
    file = params[:pdf][:tempfile]
    file_name = params[:pdf][:filename]
    file_type = params[:pdf][:type]
    file_id = upload_file(file, file_name)

    topic = TrainingTopic.find(tid)
    sub_topic = topic.training_sub_topics.find(stid)

    if file_id
      sub_topic.pdf_file = PdfFile.create(
        file_id: file_id,
        filename: file_name,
        uploaded_date: DateTime.now,
        type: file_type
      )
      sub_topic.update_attributes!(file: 'LINKED')
      Delayed::Job.enqueue(
        ConvertPdfToImages.new(sub_topic, file_id),
        queue: 'pdf_convertions',
        priority: 10,
        run_at: 5.seconds.from_now
      )
      puts "Uploaded sucessfully #{file_id}"
      flash[:info] = "Successfully uploaded presentation '#{file_id}'"
    else
      puts "Failed uploading pdf. pdf with #{file_name} already exists!."
      flash[:warning] = "Failed uploading presentation. Presentation with name '#{file_name}' already exists!."
    end
    redirect back
  end

  get '/training/topic/:tid/subtopic/:stid/ss' do |tid, stid|
    topic = TrainingTopic.find(tid)
    sub_topic = topic.training_sub_topics.find(stid)
    total_slides = sub_topic.content_slides.count

    thumbnails = []

    total_slides.times do |_sid|
      if _sid.to_i == 0
        slide_id = "first"
      elsif _sid.to_i == total_slides - 1
        slide_id = "last"
      else
        slide_id = _sid
      end

      thumbnails << {
        name: slide_id,
        data: Base64.encode64(download_file(sub_topic.content_thumbnails.find_by(name: slide_id).file_id).read)
      }
    end

    erb :slider,
      layout: :layout_slider,
      locals: {
        slides_count: total_slides,
        thumbnails: thumbnails,
        tid: tid,
        stid: stid
      }
  end

  get '/training/topic/:tid/subtopic/:stid/ss/:slideid' do |tid, stid, slideid|
    topic = TrainingTopic.find(tid)
    sub_topic = topic.training_sub_topics.find(stid)
    total_slides = sub_topic.content_slides.count

    if slideid == "0"
      slide_id = "first"
    elsif slideid == (total_slides-1).to_s
      slide_id = "last"
    else
      slide_id = params[:slideid]
    end
    _sid = sub_topic.content_slides.find_by(name: slide_id).file_id

    image_file = download_file(_sid).read
    erb :slide,
      layout: :layout_slider,
      locals: {
        image_contents: Base64.encode64(image_file)
      }
  end

  #
  # => Test routes
  #
  get '/djtest' do
    # SimpleTask.new.doit_in_5secs
    Delayed::Job.enqueue(
      CustomTask.new('lorem ipsum...'),
      queue: 'custom_tasks',
      priority: 5,
      run_at: 5.seconds.from_now
    )
    puts "dj test route"
  end

  #
  # => Generic routes
  #
  # Download a file by its id from mongo
  get '/download/:id' do |id|
    file = download_file(id)
    response.headers['content_type'] = "application/octet-stream"
    attachment(file.filename)
    response.write(file.read)
  end

  #
  # => HELPERS
  #

  # Creates an openstack connection
  def create_openstack_connection
    Fog::Compute.new({
      provider:            'openstack',
      openstack_api_key:   @settings[:openstack_api_key],
      openstack_username:  @settings[:openstack_username],
      openstack_auth_url:  @settings[:openstack_auth_url],
      openstack_tenant:    @settings[:openstack_tenant],
      connection_options:  { connect_timeout: 5 }
    })
  rescue Excon::Errors::Unauthorized
    return nil
  rescue Excon::Errors::BadRequest
    return nil
  rescue Excon::Errors::Timeout
    return nil
  end

  # Check if the specified string is an url
  def uri?(string)
    uri = URI.parse(string)
    %w(http https).include?(uri.scheme)
  rescue URI::BadURIError
    false
  rescue URI::InvalidURIError
    false
  rescue TypeError
    false
  end

  def check_captcha(ip, challenge, response)
    res = Net::HTTP.post_form(
      URI.parse('http://www.google.com/recaptcha/api/verify'),
      {
        'privatekey' => '6Lfb3fgSAAAAAHg1kT0WO6vOQylWC_SyjqqdcGuQ',
        'remoteip'   => ip,
        'challenge'  => challenge,
        'response'   => response
      }
    )

    success, error_key = res.body.lines.map(&:chomp)

    if success == 'true'
      return true
    else
      return false
    end
  end

  # Send email out using mailgun
  def send_mail(to_address, username, subject, body, campaign_id, type, tag = 'Cloudwick Email Campaigning')
    to_mail = type == 'customer' ? Settings.mailgun_customer_email : Settings.mailgun_vendor_email
    skipper = if type == 'customer'
                Customer.find_by(email: to_address)
              else
                Vendor.find_by(email: to_address)
              end
    full_name = to_mail.split('@').first.split('.')
    firstname = full_name.first.capitalize
    lastname  = if full_name.length > 1
                  full_name.last.capitalize
                else
                  nil
                end
    display_name = if lastname
                     firstname + ' ' + lastname
                   else
                     firstname
                   end
    message = if body
                 body.sub(/USERNAME/, username)
              else
                ''
              end
    if message.empty?
      # body is empty skip this email and will update the status in the vendor/customer
      # TODO: add a process to see if there are any skipped emails and send them out automatically
      skipper.udpate_attribute(:skipped, true)
      skipper.push(:skipper_subjects, subject)
    else
      RestClient.post "https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/messages",
        from: display_name + "<" + to_mail + ">",
        to: to_address,
        subject: subject,
        html: message,
        'o:campaign' => campaign_id,
        'o:tag' => tag,
        'h:Message-Id' => "#{campaign_id}@#{Settings.mailgun_domain}"
      skipper.inc(:emails_sent, 1)
    end
  end

  # campaign_type could be vendors or customers
  def create_campaign(campaign_name, campaign_id)
    unless campaign_exists?(campaign_id)
      response = RestClient.post(
        "https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/campaigns",
        name: campaign_name,
        id: campaign_id
      )
      if response.code == 200
        Campaign.find_or_create_by(_id: campaign_id) do |campaign|
          campaign.campaign_name = campaign_name
          campaign.campaign_id = campaign_id
        end
      end
    else
      Campaign.find_or_create_by(_id: campaign_id) do |campaign|
        campaign.campaign_name = campaign_name
        campaign.campaign_id = campaign_id
      end
    end
  end

  def delete_campaign(campaign_id)
    if campaign_exists?(campaign_id)
      response = RestClient.delete(
        "https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/campaigns/#{campaign_id}"
      )
    end
  end

  def campaign_exists?(campaign_id)
    exists = false
    response = RestClient.get "https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/campaigns"
    if response.code == 200
      parsed = JSON.parse(response.body, { symbolize_names: true })
      exists = true if parsed[:items].find { |ele| ele[:id] == campaign_id }
    end
    return exists
  end

  def get_campaign_stats(campaign_id)
    data = {}
    if campaign_exists?(campaign_id)
      response = RestClient.get("https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/campaigns/#{campaign_id}")
      data = JSON.parse(response.body, { symbolize_names: true })
      # puts data
      if data
        campaign = Campaign.find_by(_id: campaign_id)
        campaign.update_attributes(
          total_complained: data[:complained_count],
          total_clicked: data[:clicked_count],
          total_opened: data[:opened_count],
          total_unsubscribed: data[:unsubscribed_count],
          total_sent: data[:submitted_count],
          total_delivered: data[:delivered_count],
          total_dropped: data[:dropped_count],
          # unique_opens: data[:unique][:opened][:recipient]
        )
      end
    end
    {}
  end

  def get_campaign_sent_events
    data = []
    response =  RestClient.get("https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/stats?event=sent")
    JSON.parse(response.body, { symbolize_names: true })[:items].each do |event|
      data << [ Date.parse(event[:created_at]).strftime('%Q').to_i, event[:total_count] ]
    end
    return data.sort_by{|k| k[0]}
  end

  def get_campaign_unsubscribers
    data = {}
    response = RestClient.get("https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/unsubscribes")
    data = JSON.parse(response.body, { symbolize_names: true })
    return data
  end

  def get_campaign_bounces
    data = {}
    response = RestClient.get("https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/bounces")
    data = JSON.parse(response.body, { symbolize_names: true })
    return data
  end

  # type could be customer or vendor
  def create_route(type)
    route_name =  if type == 'customer'
                    Settings.mailgun_customer_routes_name
                  else
                    Settings.mailgun_vendor_routes_name
                  end
    match_recipient = type == 'customer' ? Settings.mailgun_customer_email : Settings.mailgun_vendor_email
    forward_emails  = type == 'customer' ? Settings.mailgun_customer_routes_forward : Settings.mailgun_vendor_routes_forward

    unless route_exists?(route_name)
      # RestClient.post("https://api:key-62-8e5xuuc0b1ojaxobl2n13mkuw4qg2@api.mailgun.net/v2/routes", priority: 0, description: 'New Route', expression: "match_recipient('jobs@mg.cloudwick.com')", action: ["forward('http://198.0.218.179/routes')"] + [ "stop()" ])
      response = RestClient.post(
        "https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/routes",
        priority: 0,
        description: route_name,
        expression: "match_recipient('#{match_recipient}')",
        action: [ "forward('http://#{Settings.bind_ip}:#{Settings.bind_port}/campaign/#{type}/reply')" ] + forward_emails.map{ |mail| "forward('#{mail}')" } + [ "stop()" ]
      )
    end
  end

  def route_exists?(route_name)
    exists = false
    response = RestClient.get("https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/routes")
    if response.code == 200
      parsed = JSON.parse(response.body, { symbolize_names: true })
      exists = true if parsed[:items].find { |ele| ele[:description] == route_name }
    end
    return exists
  end

  # Upload a file to mongo
  def upload_file(file_path, file_name)
    db = nil
    begin
      db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
      grid = Mongo::Grid.new(db)

      # Check if a file exists with the name specified
      files_db = db['fs.files']
      unless files_db.find_one({filename: file_name})
        return grid.put(
          File.open(file_path),
          filename: file_name
        ).to_s
      else
        # file already exists
        return nil
      end
    rescue
      return nil
    ensure
      db.connection.close if !db.nil?
    end
  end

  # download a file, returns a grid fs object
  def download_file(file_id)
    db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
    grid = Mongo::Grid.new(db)

    # Get the file out the db
    return grid.get(BSON::ObjectId(file_id))
    # return grid.get(resume_id)
  rescue Exception => ex
    p ex
    return nil
  ensure
    db.connection.close if !db.nil?
  end

  # Upload's a new resume using GridFS and returns id of the document
  # Onlt creates a document if there is no file exists with the same name
  def upload_resume(file_path, file_name)
    db = nil
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

  # Upload mail attachments
  def upload_attachment(file_path, file_name)
    db = nil
    begin
      db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
      grid = Mongo::Grid.new(db)
      files_db = db['fs.files']
      unless files_db.find_one({:file_name => file_name})
        return grid.put(
          File.open(file_path),
          filename: file_name
        )
      else
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

  # returns a grid fs object
  def download_attachment(attachment_id)
    db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
    grid = Mongo::Grid.new(db)

    # Get the file out the db
    return grid.get(BSON::ObjectId(attachment_id))
  rescue Exception => ex
    p ex
    return nil
  ensure
    db.connection.close if !db.nil?
  end

  # Upload document signatures
  def upload_document_signature(file_path, file_name)
    db = nil
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

  def download_document_signature(signature_id)
    db = Mongo::MongoClient.new('localhost', 27017).db('job_portal')
    grid = Mongo::Grid.new(db)

    # Get the file out the db
    return grid.get(BSON::ObjectId(signature_id))
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
