require 'rubygems'
require 'sinatra'
require 'mongo'
require 'mongoid'
require 'json'
require 'date'

require_relative 'models/sessions'
require_relative 'models/users'
require_relative 'models/consultants'
require_relative 'models/resumes'
require_relative 'models/fetcher'
require_relative 'core/process_dice'

class JobPortal < Sinatra::Base

  configure do
    Mongoid.load!("./mongoid.yml", :development)
    enable :logging, :dump_errors
    set :raise_errors, true
  end

  before do
    # MongoDB connection
    connection = Mongo::MongoClient.new('localhost', 27017)
    @database   = connection.db('job_portal')

    # Models
    @users        = UserDAO
    @sessions     = SessionDAO
    @consultants  = ConsultantsDAO.new(@database)
    @resumes      = ResumesDAO.new(@database)

    # Session Timeout
    @@expiration_date = Time.now + (60 * 2)

    # user browser cookies
    cookie = request.cookies['user_session'] || nil
    @username = begin
                  Session.find_by(_id: cookie).username
                rescue Mongoid::Errors::DocumentNotFound
                  nil
                end
  end

  get '/' do
    # even if there is no user logged in, we can show the job postings
    # show only latest 10 job postings
    # jobs = @job_postings.get_postings(10)
    erb :index
  end

  before '/jobs' do
    redirect '/login' if !@username
  end

  before '/consultants' do
    redirect '/login' if !@username
  end

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
    puts "user submitted '#{username}' with pass: '#{password}'"
    user_record = @users.validate_login(username, password)

    if user_record
      puts "Starting a session for user: #{user_record.email}"
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
    p cookie
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
      puts "user validation failed"
      erb :signup # with errors
    end
  end

  get '/jobs' do
    jobs = []
    Job.distinct(:date_posted).reverse.each do |date|
      jobs << {
        :date_url => date.strftime('%Y-%m-%d'),
        :date     => date.strftime('%A, %b %d'),
        :count    => Job.where(date_posted: date).count
      }
    end
    erb :jobs, :locals => { :jobs => jobs }
  end

  get '/job/:id' do |id|
    job = Job.find(id)
    erb :job_by_id, :locals => {:job => job}
  end

  post '/job/:id' do |id|
  end

  get '/jobs/:date' do |date|
    # process and show the jobs for a given date
    puts "about to fetch job postings for date: #{date}"
    jobs = Job.where(date_posted: date)
    erb :jobs_by_date, :locals => { :date => date, :jobs => jobs }
  end

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
      @job_processor = ProcessDicePostings.new('hadoop', 1, ['CON_CORP'])
      total_postings_max = @job_processor.total_postings
      total_postings_req = traverse_depth * 50 # user asked for this many postings to process
      total_iterations_required = if total_postings_req > total_postings_max
                                    total_postings_max
                                  else
                                    total_postings_req
                                  end
      percentage_for_url_processing = 5
      percentage_per_iteration = ( 90.to_f / total_iterations_required )
      @jobs_to_process = []
      child_pid = Process.fork do
        p 'Gathering URLs to process'
        Fetcher.last.update_attribute(:message, 'Gathering URLs to process')
        begin
          traverse_depth.times do |page|
            p "Processing urls for page: #{page + 1}"
            @job_processor.get_urls(page).each do |job_posting|
              @jobs_to_process << job_posting
            end
          end
        rescue Exception => ex
          Fetcher.last.update_attribute(:message, ex)
          Fetcher.last.update_attribute(:job_status, 'failed')
          return
        end
        Fetcher.last.inc(:total_jobs_to_process, @jobs_to_process.length)
        Fetcher.last.inc(:progress, percentage_for_url_processing)
        Fetcher.last.update_attribute(:message, 'Processing URLs')
        p 'Processing URLs'
        begin
          @jobs_to_process.each do |job|
            # p "Processing job posting: #{job}"
            @job_processor.process_job_postings(job)
            Fetcher.last.inc(:progress, percentage_per_iteration)
            Fetcher.last.inc(:jobs_processed, 1)
          end
        rescue Exception => ex
          Fetcher.last.update_attribute(:message, ex)
          Fetcher.last.update_attribute(:job_status, 'failed')
          return
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

  get '/consultants' do
    erb :consultants
  end

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
