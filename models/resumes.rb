class ResumesDAO
  attr_accessor :db, :resumes

  def initialize(database)
    @db = database
    @resumes = database['resume']
  end

  def insert_resume(rid, file, last_updated, uid)
    resume = {
      '_id' => rid,
      'file' => file,
      'last_updated' => last_updated,
      'uid' => uid
    }

    begin
      @resumes.insert(resume)
    rescue
      puts "Error inserting resume"
      puts "Unexpected Error: #{$!}"
    end
  end
end
