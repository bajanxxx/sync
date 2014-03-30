require 'rubygems'
require 'sinatra'
require 'mongo'
require 'json'

require_relative 'models/sessions'
require_relative 'models/users'
require_relative 'models/consultants'
require_relative 'models/resumes'
require_relative 'models/job_postings'
require_relative 'models/fetcher'
require_relative 'core/process_dice'

class JobPortal < Sinatra::Base

  configure do
    # LOGGER = Logger.new("job_portal.log")
    enable :logging, :dump_errors
    set :raise_errors, true
  end

  before do
    # MongoDB connection
    connection = Mongo::MongoClient.new('localhost', 27017)
    @database   = connection.db('job_portal')

    # Models
    @users        = UserDAO.new(@database)
    @sessions     = SessionDAO.new(@database)
    @consultants  = ConsultantsDAO.new(@database)
    @job_postings = JobPostingsDAO.new(@database)
    @resumes      = ResumesDAO.new(@database)
    @fetcher      = FetcherDAO.new(@database)

    # Session Timeout
    @@expiration_date = Time.now + (60 * 2)

    # user browser cookies
    cookie = request.cookies['user_session'] || nil
    @username = @sessions.get_username(cookie)
  end

  before '/jobs' do
    redirect '/login' if !@username
  end

  before '/consultants' do
    redirect '/login' if !@username
  end

  # before '/consultants/*' do
  #   if !@username
  #     halt.erb(:login)
  #   end
  # end

  get '/' do
    # even if there is no user logged in, we can show the job postings
    # jobs = @job_postings.get_postings(10)
    erb :index
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
      session_id = @sessions.start_session(user_record['_id'])
      redirect '/internal_error' unless session_id
      cookie = session_id
      response.set_cookie(
          'user_session',
          :value => cookie,
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
      puts "user validation failed"
      erb :signup # with errors
    end
  end

  get '/jobs' do
    erb :jobs
  end

  get '/jobs/fetch_now' do
    @fetcher.create_job_session
    traverse_depth = 1
    @job_processor = ProcessDicePostings.new('hadoop', 1, ['CON_CORP'], @database)
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
      @fetcher.update_fetcher_message('Gathering URLs to process')
      begin
        traverse_depth.times do |page|
          p "Processing urls for page: #{page + 1}"
          @job_processor.get_urls(page).each do |job_posting|
            @jobs_to_process << job_posting
          end
        end
      rescue Exception => ex
        @fetcher.update_fetcher_message(ex)
        @fetcher.update_fetcher_state('failed')
        return
      end
      @fetcher.update_total_jobs_to_process(@jobs_to_process.length)
      @fetcher.update_progress(percentage_for_url_processing)
      @fetcher.update_fetcher_message('Processing URLs')
      p 'Processing URLs'
      begin
        @jobs_to_process.each do |job|
          p "Processing job posting: #{job}"
          @job_processor.process_job_postings(job)
          @fetcher.update_progress(percentage_per_iteration)
          @fetcher.update_jobs_processed(1)
        end
      rescue Excetion => ex
        @fetcher.update_fetcher_message(ex)
        @fetcher.update_fetcher_state('failed')
        return
      end
      @fetcher.update_fetcher_message('completed with no errors')
      @fetcher.update_fetcher_state('completed')
      Process.exit
    end
    Process.detach child_pid

    erb :fetch_now
  end

  get '/jobs/fetch_now/progress' do
    # returns how much progress has been made so far
    stat = @fetcher.get_fetcher_latest_stat
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
