class FetcherDAO
  attr_accessor :db, :fetcher_stats

  def initialize(database)
    @db = database
    @fetcher_stats = database["fetcher_stats"]
  end

  def get_latest_id
    @fetcher_stats.find.sort(:_id => :desc).limit(1).to_a.first['_id']
  end

  def create_job_session
    fetcher_instance = {
      job_status: 'running',
      progress: 5,
      jobs_fetched: 0,
      message: 'Initializing',
      jobs_processed: 0,
      total_jobs_to_process: 0,
      time_instantiated: Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")
    }
    begin
      @fetcher_stats.insert(fetcher_instance)
    rescue Mongo::OperationFailure => e
      puts "[Error]: oops, mongo error, #{$!}"
      return false
    end
  end

  def update_progress(progress = 1)
    @fetcher_stats.update({_id: get_latest_id}, {:$inc => {:progress => progress}})
  end

  def update_jobs_processed(processed = 1)
    @fetcher_stats.update({_id: get_latest_id}, {:$inc => {:jobs_processed => processed}})
  end

  def update_total_jobs_to_process(jobs = 0)
    @fetcher_stats.update({_id: get_latest_id}, {:$inc => {:total_jobs_to_process => jobs}})
  end

  def update_fetched_jobs(jobs = 0)
    @fetcher_stats.update({_id: get_latest_id}, {:$inc => {:jobs_fetched => jobs}})
  end

  def update_fetcher_state(state = 'running')
    @fetcher_stats.update({_id: get_latest_id}, {:$set => {:job_status => state}})
  end

  def update_jobs_fetched(count = 0)
    @fetcher_stats.update({_id: get_latest_id}, {:$set => {:jobs_fetched => count}})
  end

  def update_fetcher_message(message)
    @fetcher_stats.update({_id: get_latest_id}, {:$set => {:message => message}})
  end

  def get_fetcher_latest_stat
    stat = @fetcher_stats.find_one({_id: get_latest_id})
    {
      :job_status => stat['job_status'],
      :progress => stat['progress'],
      :jobs_fetched => stat['jobs_fetched'],
      :time_instantiated => stat['time_instantiated'],
      :jobs_processed => stat['jobs_processed'],
      :total_jobs_to_process => stat['total_jobs_to_process'],
      :message => stat['message']
    }
  end

  def get_fetcher_stats(count = 10)
    cursor = Array.new
    cursor = @fetcher_stats.find.limit(count)

    stats = Array.new
    cursor.each do |stat|
      stats << {
        :_id => stat['_id'],
        :job_status => stat['job_status'],
        :progress => stat['progress'],
        :jobs_fetched => stat['jobs_fetched'],
        :time_instantiated => stat['time_instantiated'],
        :jobs_processed => stat['jobs_processed'],
        :total_jobs_to_process => stat['total_jobs_to_process']
      }
    end
    stats
  end
end
