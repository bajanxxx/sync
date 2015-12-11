class ConsultantsDAO
  attr_accessor :db, :posts

  def initialize(database)
    @db = database
    @consultants = database['consultants']
  end

  def add_consultant(cid, cname, team)
    puts "Inserting user with cid: #{cid} to team: #{team}"

    consultant = {
      :_id        => cid,
      :cname      => cname,
      :team       => team,
      :applied_to => []
    }

    begin
      @consultants.insert(consultant)
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

  def add_applied_to(cid, job_id, comments, resume_file_name, resume_path)
    applied_to = {
      :job_id    => job_id,
      :comments  => comments,
      :resume_id => upload_resume(resume_file_name, resume_path)
    }

    begin
      query = {'_id' => cid}
      consultant = @consultants.find_one(query)
      applied_to_list = consultant['applied_to']
      applied_to_list << applied_to
      @consultants.save(consultant)
    rescue
      puts "Could not update the collection, error"
      puts "Unexpected Error, #{$!}"
    end
  end

  def get_consultants(limit = 10)
    cursor = Array.new
    cursor = @consultants.find.limit(limit)

    consultants = Array.new
    cursor.each do |consultant|
      consultants << {
        :cid => consultant['_id'],
        :name => consultant['cname'],
        :team => consultant['team'],
        :applied_to => consultant['applied_to']
      }
    end
    consultants
  end

  def get_consultant_by_id(cid)
    @consultants.find_one({:_id => cid})
  end

  def get_resume_ids_for_consultant(cid, limit = 5)
    consultant = get_consultant_by_id(cid)
    applied_to = consultant['applied_to']
    if applied_to.is_a?(Array) && !applied_to.empty?
      rid = Array.new
      applied_to.each do |a|
        rid << a['resume_id']
      end
      return rid
    else
      puts "No resumes found for user"
    end
  end

  # uses gridfs to upload a document on mongo and returns the id of that file
  # get the file back using `file = fs.get(BSON::ObjectId(id))`. Following metadata can be
  # retrieved: `file.filename`, `file.content_type`, `file.file_length`,
  #   `file.upload_date`, `file.read`(read all data at once),
  #   `file.read (100 * 1024)`(read the first 100k bytes of file data)
  # & finally to delete a file `fs.delete(id2)`
  def upload_resume(file_name, file_path)
    fs = Mongo::Grid.new(@db)
    file = File.open(file_path)
    id = fs.put(
           file,
           :filename => file_name,
           :content_type => 'application/msword',
           :chunk_size => 100 * 1024,
           :metadata => { 'description' => "Belongs to consultant x using for applying y position" }
         )
    id
  end

  def download_resume(file_id)
    fs = Mongo::Grid.new(@db)
    begin
      file_id = BSON::ObjectId(file_id) if file_id.is_a?(String)
      file = fs.get(file_id)
      return file.read
    rescue BSON::InvalidObjectId
      puts "[Error]: Illegal ObjectId format: #{file_id}"
    rescue Mongo::GridFileNotFound
      puts "[Error]: Cannot find file with file_id: #{file_id.to_s}"
    end
  end
end
