require 'net/http'
require 'open-uri'
require 'pp'
require 'pathname'
require 'optparse'
require 'ostruct'
require 'mongoid'
require 'mongoid_search'
require 'parallel'

require_relative '../app/models/job'
require_relative '../app/models/application'
require_relative '../app/models/fetcher'

class FetchPostings
  def initialize(base_url, search_string, age, pages_to_traverse, page_search)
    @traverse_depth     = pages_to_traverse.to_i
    @base_url           = base_url
    @search_string      = search_string
    @page_search_string = page_search
    @age                = age
    @processed_data     = Hash.new
    @mutex              = Mutex.new
    @processed          = 0
    @total_postings_max = total_postings
    @total_postings_req = pages_to_traverse * 50 # user asked for this many postings to process
    @total_messages_to_process = if @total_postings_req > @total_postings_max
                                  @total_postings_max
                                else
                                  @total_postings_req
                                end
  end

  def process_request(base_url, params = {})
    uri       = URI.parse(base_url)
    uri.query = URI.encode_www_form(params) unless params.nil?
    printf "Processing page request (#{uri})\n"
    response = Net::HTTP.get_response(uri)
    if response.code == '301' || response.code == '302'
      response = Net::HTTP.get_response(URI.parse(response.header['location']))
    end
    return response
  rescue URI::InvalidURIError
    $stderr.printf "Failed parsing URL: #{base_url}\n"
    return nil
  end

  def process_response(response)
    json = JSON.parse(response.body)
    total_docs = json['count']
    last_doc_in_page = json['lastDocument']
    printf "Processing postings: #{last_doc_in_page} | Total postings: #{total_docs} | Total processed: #{@processed}\n"
    result = json['resultItemList']
    Parallel.each(result, :in_threads => 50) do |rs|
      @mutex.synchronize { @processed += 1 }
      response_internal = process_request(rs['detailUrl'])
      if keep_posting?(response_internal)
        @mutex.synchronize {
          @processed_data[rs['detailUrl']] = {
            :title => rs['jobTitle'],
            :company => rs['company'],
            :location => rs['location'],
            :date_posted => rs['date'],
            :skills => pull_skills(response_internal),
            :email  => pull_emails(response_internal),
            :phone_nums => pull_phones(response_internal)
          }
        }
      end
    end
    return if total_docs.to_i == last_doc_in_page.to_i
  end

  # Get the total number of job postings for a specified search string
  def total_postings
    res = process_request(@base_url, params = {:text => @search_string, :age => @age})
    JSON.parse(res.body)['count'].to_i
  end

  def total_message_to_process
    @total_messages_to_process
  end

  # figure out if the posting is to be kept based on 'Tax Term: *CON_CORP*'
  def keep_posting?(response)
    return false if response.nil?
    status = true
    if @page_search_string
      @page_search_string.each do |ps|
        unless response.body =~ Regexp.new(ps)
          status = false
        end
      end
    end
    return status
  end

  def pull_skills(response)
    skills = response.body.scan(Regexp.new('^\s+<dt.*>Skills:<\/dt>\s+<dd.*>(.*)<\/dd>')).first
    if skills.is_a?(Array)
      return skills.map {|e| e.gsub('&nbsp;', '')}
    else
      []
    end
  end

  def pull_emails(response)
    emails = response.body.scan(Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')).uniq - ['email@domain.com']
    if emails.is_a?(Array)
      return emails
    else
      []
    end
  end

  def pull_phones(response)
    # TEN_DIGITS = /^\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/
    # SEVEN_DIGITS = /^(?:\(?([0-9]{3})\)?[-. ]?)?([0-9]{3})[-. ]?([0-9]{4})$/
    # LEADING_1 = /^(?:\+?1[-. ]?)?\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/
    phns = response.body.scan(Regexp.new('/^\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/')).uniq
    if phns.is_a?(Array)
      return phns
    else
      []
    end
  end

  def run
    @traverse_depth.times do |page|
      response = process_request(
        @base_url,
        params = {
          :text => @search_string,
          :age  => @age,
          :page => page + 1,
          :sort => 1
        }
      )
      process_response(response)
    end
    return @processed_data
  end
end

if __FILE__ == $0
  options  = OpenStruct.new
  # defaults
  options.encrypt = false
  options.age_of_postings = 1
  options.traverse_depth  = 1
  options.page_search_string = []
  req_options = %w(search_string)

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

    opts.on('-s', '--search STRING', "Specify a search string like a keyword on which to filter job postings. For example: 'java' or 'ruby'.") do |s|
      options.search_string = s
    end

    opts.on('-a', '--age-of-postings [DAYS]', Numeric, "Specifies how many days back postings to fetch.") do |a|
      options.age_of_postings = a
    end

    opts.on('-d', '--traverse-depth [DEPTH]', Numeric, "How many pages to traverse (each page contains 50 postings)") do |t|
      options.traverse_depth = t
    end

    opts.on('-r', '--page-search [STRING]', "Specify a search term to traverse to job posting and do a regex search") do |r|
      options.page_search_string << r
    end

    opts.on('--help', 'Show this message') do
      puts opts
      exit
    end
  end

  begin
    optparse.parse!
    req_options.each do |req|
      raise OptionParser::MissingArgument, req if options.send(req).nil?
    end
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument
    puts $!.to_s
    puts optparse
    exit
  end

  puts "Initializing fetcher @ #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

  Mongoid.load!(File.expand_path('config/mongoid.yml', File.dirname(__FILE__)), :development)

  processor = ProcessPostings.new(
    'http://service.dice.com/api/rest/jobsearch/v1/simple.json',
    options.search_string,
    options.age_of_postings,
    options.traverse_depth,
    options.page_search_string
  )

  data = processor.run

  inserted_docs = 0

  puts "Updating job postings"
  data.each do |url, job_posting|
    # Only insert if a posting with date and url does not exist
    Job.find_or_create_by(url: url, date_posted: job_posting[:date_posted]) do |doc|
      inserted_docs += 1
      doc.search_term = options.search_string.downcase
      doc.url         = url
      doc.source      = 'DICE'
      doc.date_posted = job_posting[:date_posted]
      doc.title       = job_posting[:title]
      doc.company     = job_posting[:company]
      doc.location    = job_posting[:location]
      doc.skills      = job_posting[:skills]
      doc.emails      = job_posting[:emails]
      doc.phone_nums  = job_posting[:phone_nums]
      # If the url previously exists in the dataset with different date_posted and
      # marked as **forget** then mark make post as hidden.
      doc.hide = true if Job.where(url: url, hide: true).count > 1
    end
  end

  puts "Writing Fetcher Stats"
  Fetcher.create(
    job_status:     'completed',
    progress:       100.0,
    jobs_filtered:  data.count,
    message:        'Initializing',
    jobs_processed: processor.total_message_to_process,
    init_time:      DateTime.now,
    jobs_inserted:  inserted_docs
  )
end
