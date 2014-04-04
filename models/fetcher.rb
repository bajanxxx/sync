# Get lastest document => Fetcher.last
class Fetcher
  include Mongoid::Document
  # store_in collection: "fetcher_stats"

  field :job_status,            type: String
  field :progress,              type: Float
  field :jobs_filtered,         type: Integer
  field :jobs_inserted,         type: Integer
  field :message,               type: String
  field :jobs_processed,        type: Integer
  field :total_jobs_to_process, type: Integer
  field :init_time,             type: DateTime
end
