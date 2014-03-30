class JobPostingsDAO
  def initialize(database)
    @db = database
    @job_postings = database["postings"]
  end

  def get_poting_by_url(url)
    @job_postings.find_one({:_id => url})
  end

  def get_postings(num_postings = 10)
    cursor = Array.new
    cursor = @job_postings.find.limit(num_postings)

    postings = Array.new
    cursor.each do |posting|
      postings << {
        :url => posting['_id'],
        :date_posted => posting['date_posted'],
        :title => posting['title'],
        :company => posting['company'],
        :location => posting['location'],
        :skills => posting['skills']
      }
    end
    postings
  end

  # Query the avaialble dates for job postings and sort them
  def get_dates(limit = 10)
    dates = @job_postings.distinct(:date_posted)
    dates.sort_by{|d| Date.parse(d)}.reverse![0..limit]
  end

  def get_postings_count_for_date(date)
    @job_postings.find({:date_posted => date}).count
  end

  def add_posting(url, date_posted, title, company, location, skills, emails, phone_nums)
    posting = {
      :_id         => url,
      :date_posted => date_posted,
      :title       => title,
      :company     => company,
      :location    => location,
      :skills      => skills,
      :emails      => emails,
      :phone_nums  => phone_nums
    }

    begin
      # 'save' is safer than insert, if the document already has an '_id' key,
      # then an update (upsert) operation will be performed, and any existing
      # document with that _id is overwritten. Otherwise an insert operation is
      # performed.
      @job_postings.save(posting)
    rescue Mongo::OperationFailure => e
      if e.message =~ /^11000/
        puts "[Error]: Duplicate key error #{$!}"
        return false
      else
        puts "[Error]: oops, mongo error, #{$!}"
        return false
      end
    end
    return true
  end
end
