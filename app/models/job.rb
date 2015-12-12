class Job
  include Mongoid::Document

  SOURCES = [ :dice, :indeed, :internal ]
  SEARCH_TERMS = [ :hadoop, :cassandra, :spark ]

  field :search_term, type: String
  field :source,      type: String # Specify what the source is DICE, INDEED, INTERNAL
  field :url,         type: String
  field :date_posted, type: Date
  field :title,       type: String
  field :company,     type: String
  field :location,    type: String
  field :skills,      type: Array
  field :emails,      type: Array
  field :phone_nums,  type: Array
  field :read,        type: Boolean, default: false # specify whether a job posting has been read previously
  field :hide,        type: Boolean, default: false # specify whether a user want this post to be hidden
  field :desc,        type: String
  field :trigger,     type: Array # possible triggers => [ 'SEND_TO_VENDOR', 'SEND_TO_CONSULTANT', 'CHECK_LATER', 'APPLY' ]
  field :link_active, type: Boolean, default: true # specify whether a job posting link is active or not
  field :repeated,    type: Boolean, default: false # specify if this job posting is repeated
  field :pdates,      type: Array, default: [] # if this is a repeated job posting store the previous data_posted's in here
  field :version,     type: Numeric # 1 and 2. v2 (version 2) is for jobs from scala fetcher

  index({ url: 1 }, { unique: true, name: "url_index" })

  has_many :applications, class_name: 'Application'

  SOURCES.each do |source|
    # Get all the jobs for a specified source.
    #
    # @example Get all jobs from dice.
    #   Job.dice_jobs
    #
    # @example Get all jobs from indeed.
    #   Job.indeed_jobs
    #
    # @example Get all jobs from internal sources.
    #   Job.internal_jobs
    #
    # @return [ Array<Job> ] The matching jobs.
    scope "#{source}_jobs", -> { where(source: source.to_s.upcase) }
  end

  SEARCH_TERMS.each do |search_term|
    # Get all the jobs for a specified search_term.
    #
    # @example Get all hadoop jobs from all sources.
    #   Job.hadoop_jobs
    #
    # @example Get all cassandra jobs from all sources.
    #   Job.cassandra_jobs
    #
    # @example Get all spark jobs from all sources.
    #   Job.spark_jobs
    #
    # @return [ Array<Job> ] The matching jobs.
    scope "#{search_term.to_s}_jobs", -> { where(search_term: search_term.to_s) }
  end

  class << self
    SOURCES.each do |source|
      SEARCH_TERMS.each do |search_term|
        # Get all the jobs for the all possible combinations of SOURCE and SEARCH_TERMS
        #
        # @example Get hadoop jobs from dice posted last 7 days.
        #   Job.dice_hadoop_jobs_week
        #
        # @example Get hadoop jobs from indeed posted last 7 days.
        #   Job.indeed_hadoop_jobs_week
        #
        # @example Get hadoop jobs from internal sources posted last 7 days.
        #   Job.internal_hadoop_jobs_week
        #
        # @example Get "SOURCE" jobs from "SEARCH_TERM" sources posted in the last 7 days.
        #   Job."#{source}_#{search_term}_jobs_week"
        #
        # @return [ Array<Job> ] The matching jobs.
        define_method "#{source.to_s}_#{search_term.to_s}_jobs_week" do
          where(
            search_term: search_term.to_s,
            source: source.to_s.upcase,
            :date_posted.lte => Date.today,
            :date_posted.gt => (Date.today-7),
            hide: false
          )
        end

        # Get all the jobs for the all possible combinations of SOURCE and SEARCH_TERMS for a given date
        #
        # @example Get hadoop jobs from dice posted for a specified date.
        #   Job.dice_hadoop_jobs_day(date)
        #
        # @example Get hadoop jobs from indeed posted for a specified date.
        #   Job.indeed_hadoop_jobs_day(date)
        #
        # @example Get hadoop jobs from internal sources posted for a specified date.
        #   Job.internal_hadoop_jobs_day(date)
        #
        # @example Get "SOURCE" jobs from "SEARCH_TERM" sources posted for a specified date.
        #   Job."#{source}_#{search_term}_jobs_week(date)"
        #
        # @return [ Array<Job> ] The matching jobs.
        define_method "#{source.to_s}_#{search_term.to_s}_jobs_day" do |date|
          where(
            search_term: search_term.to_s,
            source: source.to_s.upcase,
            date_posted: date,
            hide: false
          )
        end
      end
    end
  end

end
