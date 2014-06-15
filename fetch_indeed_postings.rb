require 'net/http'
require 'open-uri'
require 'pp'
require 'pathname'
require 'optparse'
require 'ostruct'
require 'mongoid'
require 'mongoid_search'
require 'parallel'
require 'colored'
require 'nokogiri'
require 'timeout'

require_relative 'models/job'
require_relative 'models/application'
require_relative 'models/fetcher'

class ProcessURL
  def self.process_request(base_url, params = {}, limit = 10)
    raise ArgumentError, 'HTTP redirect too deep' if limit == 0
    uri       = URI.parse(base_url)
    uri.query = URI.encode_www_form(params) unless params.nil?
    printf "Processing page request (#{uri.to_s.gsub('%', '%%')})\n".blue
    response = nil
    begin
      Timeout::timeout(10) do
        response = Net::HTTP.get_response(uri)
        if response.code == '301' || response.code == '302'
          printf "Following redirection to process #{response.header['location'].gsub('%', '%%')}\n".cyan
          response = process_request(response.header['location'], nil, limit - 1)
        end
        return response
      end
    rescue Timeout::Error
      puts "Failed to parse request in 10 seconds, skipping.".red
    end
  rescue URI::InvalidURIError
    $stderr.printf "Failed parsing URL: #{base_url}\n".red
    return nil
  rescue Errno::ECONNREFUSED
    $stderr.printf "Failed parsing URL: #{base_url}. Reason: connection refused.\n".red
    return nil
  end

  def self.pull_skills(response)
    skills = response.body.scan(Regexp.new('^\s+<dt.*>Skills:<\/dt>\s+<dd.*>(.*)<\/dd>')).first if response
    if skills.is_a?(Array)
      return skills.map {|e| e.gsub('&nbsp;', '')}
    else
      []
    end
  end

  def self.pull_emails(response)
    emails = response.body.scan(Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')).uniq - ['email@domain.com'] if response
    if emails.is_a?(Array)
      return emails
    else
      []
    end
  end

  def self.pull_phones(response)
    # TEN_DIGITS = /^\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/
    # SEVEN_DIGITS = /^(?:\(?([0-9]{3})\)?[-. ]?)?([0-9]{3})[-. ]?([0-9]{4})$/
    # LEADING_1 = /^(?:\+?1[-. ]?)?\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/
    phns = response.body.scan(Regexp.new('/^\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/')).uniq if response
    if phns.is_a?(Array)
      return phns
    else
      []
    end
  end
end

class ProcessIndeedPostings
  def initialize(base_url, publisher_id, query, age, job_type, limit = 100, version = 2)
    @indeed_base_url        = base_url
    @indeed_age             = age
    @indeed_query           = query
    @publisher_id           = publisher_id
    @job_type               = job_type
    @version                = version
    @limit                  = limit
    @indeed_processed_posts = 0
    @indeed_processed       = Hash.new
    @indeed_mutex           = Mutex.new
    @total_messages_to_process = limit
  end

  # parses xml response from api
  def process_response(response)
    xml = Nokogiri::XML.parse(response.body).xpath("//results//result")
    Parallel.each(xml, :in_threads => 50) do |job_posting|
      @indeed_mutex.synchronize { @indeed_processed_posts += 1 }
      uri = URI.parse(job_posting.at('url').text.gsub("\n", ''))
      # Fetch the indivual job posting details
      internal_reponse = ProcessURL.process_request(
        'http://api.indeed.com/ads/apigetjobs',
        params = {
          jobkeys: CGI.parse(uri.query)['jk'],
          publisher: @publisher_id,
          v: @version
        }
      )
      Nokogiri::XML.parse(internal_reponse.body).xpath("//results//result").each do |rs|
        job_uri = URI.parse(rs.at('url').text)
        raw_job_html = ProcessURL.process_request("#{job_uri.scheme}://#{job_uri.host}#{job_uri.path}", CGI.parse(job_uri.query))
        @indeed_mutex.synchronize {
          @indeed_processed[rs.at('url').text] = {
            title: rs.at('jobtitle').text,
            company: rs.at('company').text,
            desc: rs.at('snippet').text,
            location: rs.at('formattedLocation').text,
            date_posted: Date.parse(rs.at('date').text.gsub("\n", '')).strftime('%Y-%m-%d'),
            source: rs.at('source').text,
            skills: ProcessURL.pull_skills(raw_job_html),
            email: ProcessURL.pull_emails(raw_job_html),
            phone_nums: ProcessURL.pull_phones(raw_job_html)
          }
        }
      end
    end
    # Nokogiri::XML.parse(response).xpath("//results//result").map do |job|
    #   %w(jobtitle company city state formattedLocation source date snippet url).each_with_object({}) do |elementName, object|
    #     if elementName == 'date'
    #       object[elementName] = Date.parse(job.at(elementName).text.gsub("\n", '')).strftime('%Y-%m-%d')
    #     else
    #       object[elementName] = job.at(elementName).text.gsub("\n", '')
    #     end
    #   end
    # end
  end

  def total_messages_to_process
    @total_messages_to_process
  end

  def run
    response = ProcessURL.process_request(
      @indeed_base_url,
      params = {
        publisher: @publisher_id,
        v: @version,
        q: @indeed_query,
        jt: @job_type,
        fromage: @indeed_age,
        limit: @limit
      }
    )
    process_response(response)
    return @indeed_processed
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

    opts.on('-l', '--limit [POSTINGS]', Numeric, "Number of postings to fetch") do |l|
      options.limit = l
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

  processor = ProcessIndeedPostings.new(
    'http://api.indeed.com/ads/apisearch',
    '2189777535626080', # publisher_id
    options.search_string,
    options.age_of_postings,
    'contract', # job type
    options.limit,
    2 # api_version
  )

  data = processor.run

  inserted_docs = 0

  puts "Updating indeed job postings"
  data.each do |url, job_posting|
    # Only insert if a posting with date and url does not exist
    Job.find_or_create_by(url: url, date_posted: job_posting[:date_posted]) do |doc|
      inserted_docs += 1
      doc.search_term = options.search_string.downcase
      doc.url         = url
      doc.source      = 'INDEED'
      doc.date_posted = job_posting[:date_posted]
      doc.title       = job_posting[:title]
      doc.company     = job_posting[:company]
      doc.location    = job_posting[:location]
      doc.desc        = job_posting[:desc]
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
    jobs_processed: processor.total_messages_to_process,
    init_time:      DateTime.now,
    jobs_inserted:  inserted_docs
  )
end
