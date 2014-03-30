require 'net/http'
require 'open-uri'
require 'json'
require 'parallel'
require_relative '../models/job_postings'
require_relative '../models/fetcher'

class ProcessDicePostings
  attr_accessor :id, :processed, :processed_data

  def initialize(search_string, age, page_search, database)
    @base_url           = "http://service.dice.com/api/rest/jobsearch/v1/simple.json"
    @search_string      = search_string
    @page_search_string = page_search
    @age                = age
    @processed_data     = Hash.new
    @mutex              = Mutex.new
    @processed          = 0
    @job_postings       = JobPostingsDAO.new(database)
    # @fetcher_stats      = FetcherDAO.new(database)
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
      @job_postings.add_posting(
        job_posting['detailUrl'],
        job_posting['date'],
        job_posting['jobTitle'],
        job_posting['company'],
        job_posting['location'],
        pull_skills(res),
        pull_email(res),
        pull_phone(res) || 'N/A'
      )
    end
  end

  # def process(page)
  #   response = process_request(
  #     @base_url,
  #     params = {
  #       :text => @search_string,
  #       :age  => @age,
  #       :page => page + 1,
  #       :sort => 1
  #     }
  #   )
  #   process_response(response) # process all job postings in specified page
  # end

  # def process_response(response)
  #   json = JSON.parse(response.body)
  #   total_docs = json['count']
  #   last_doc_in_page = json['lastDocument']
  #   printf "Processing postings: #{last_doc_in_page} | Total postings: #{total_docs} | Total processed: #{@processed}\n"
  #   result = json['resultItemList']
  #   Parallel.each(result, :in_threads => @threads_to_process) do |rs|
  #     @mutex.synchronize { @processed += 1 }
  #     response_internal = process_request(rs['detailUrl'])
  #     if keep_posting?(response_internal)
  #       @mutex.synchronize {
  #         @processed_data[rs['detailUrl']] = {
  #           :title => rs['jobTitle'],
  #           :company => rs['company'],
  #           :location => rs['location'],
  #           :date => rs['date'],
  #           :skills => pull_skills(response_internal) || nil,
  #           :email  => pull_email(response_internal) || nil
  #         }
  #       }
  #     end
  #     # iteration 1 complete 25 records processed update progress
  #   end
  #   @fetcher_stats.update_progress(@percentage_per_iteration)
  #   return if total_docs.to_i == last_doc_in_page.to_i
  # end

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
      return skills.join(',').gsub('&nbsp;', '')
    else
      'N/A'
    end
  end

  def pull_email(response)
    emails = response.body.scan(Regexp.new('\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b')).uniq - ['email@domain.com']
    if emails.is_a?(Array)
      return emails.join(',')
    else
      'N/A'
    end
  end

  def pull_phone(response)
    # TEN_DIGITS = /^\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/
    # SEVEN_DIGITS = /^(?:\(?([0-9]{3})\)?[-. ]?)?([0-9]{3})[-. ]?([0-9]{4})$/
    # LEADING_1 = /^(?:\+?1[-. ]?)?\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/
    phns = response.body.scan(Regexp.new('/^\(?([0-9]{3})\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})$/')).uniq
    if phns.is_a?(Array)
      return phns.join(',')
    else
      'N/A'
    end
  end


  # def run!
  #   @traverse_depth.times do |page_count|
  #     begin
  #       process(page_count)
  #     rescue Exception => ex
  #       p ex
  #       @fetcher_stats.update_fetcher_state('failed')
  #       return false
  #     end
  #   end
  #   # Add job postings to mongo
  #   begin
  #     @processed_data.each do |url, cols|
  #       @job_postings.add_posting(
  #         url,
  #         cols[:date],
  #         cols[:title],
  #         cols[:company],
  #         cols[:location],
  #         cols[:skills],
  #         cols[:email],
  #         cols[:phone] || 'N/A'
  #       )
  #     end
  #   rescue Exception => ex
  #     p ex
  #     @fetcher_stats.update_fetcher_state('failed')
  #     return false
  #   end
  #   # we are done here, set job status as completed
  #   @fetcher_stats.update_progress(@percentage_for_mongo)
  #   @fetcher_stats.update_fetcher_state('completed')
  #   return true
  # end
end
