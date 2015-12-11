require 'net/http'
require 'open-uri'
require 'json'
require 'parallel'

require_relative '../app/models/job'
require_relative '../app/models/fetcher'

class ProcessDicePostings
  attr_accessor :id, :processed, :processed_data

  def initialize(search_string, age, page_search)
    @base_url           = "http://service.dice.com/api/rest/jobsearch/v1/simple.json"
    @search_string      = search_string
    @page_search_string = page_search
    @age                = age
    @processed_data     = Hash.new
    @mutex              = Mutex.new
    @processed          = 0
    @inserted           = 0
  end

  # Process a http request using net/http, also follow redirect's one level deep
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

  # Get the total number of job postings for a specified search string
  def total_postings
    res = process_request(@base_url, params = {:text => @search_string, :age => @age})
    JSON.parse(res.body)['count'].to_i
  end

  # Fetches the job postings for specified page number, each page has 50
  # job postings
  def get_urls(page)
    response = process_request(
      @base_url,
      params = {
        :text => @search_string,
        :age  => @age,
        :page => page + 1, # page number to process
        :sort => 1 # sort in ascending order by date
      }
    )
    JSON.parse(response.body)['resultItemList']
  end

  # Process each job posting url as recieved from #get_urls and put the
  # processed job information into mongo
  def process_job_postings(job_posting)
    res = process_request(job_posting['detailUrl'])
    if keep_posting?(res)
      # Only create a document if the url does not exist
      url = job_posting['detailUrl']
      Job.find_or_create_by(url: url, date_posted: job_posting['date']) do |doc|
        doc.url         = url
        doc.search_term = @search_string.downcase
        doc.date_posted = job_posting['date']
        doc.title       = job_posting['jobTitle']
        doc.company     = job_posting['company']
        doc.location    = job_posting['location']
        doc.skills      = pull_skills(res)
        doc.emails      = pull_email(res)
        doc.phone_nums  = pull_phone(res)
        Fetcher.last.inc(:jobs_inserted, 1)
      end
      Fetcher.last.inc(:jobs_filtered, 1)
    end
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

  def pull_email(response)
    emails = response.body.scan(Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')).uniq - ['email@domain.com']
    if emails.is_a?(Array)
      return emails
    else
      []
    end
  end

  def pull_phone(response)
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
end
