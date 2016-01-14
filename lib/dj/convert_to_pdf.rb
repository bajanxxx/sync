require 'tempfile'
require 'fileutils'

class ConvertPdfToImages < Struct.new(:sub_topic, :file_id, :settings)

  def perform
    local_file = "/tmp/#{file_id}.pdf"
    begin
      sub_topic.update_attributes!(lock?: true, state: 'PROCESSING')
      log 'Fetching the file from Mongo to convert'
      # fetch the pdf from mongo and write it to local fs
      file_contents = download_file(file_id).read
      if file_contents.nil? || file_contents.empty?
        raise 'File contents are empty. Cannot get the file from Mongo.'
      else
        log "Writing pdf file to temp location #{local_file}"
        File.open(local_file, 'w') { |_f| _f.write(file_contents) }
        # convert pdf to images
        log 'Converting PDF file to images with a density setting of 600.'
        pdf_images = Magick::ImageList.new(local_file) { self.density = 600 }

        # iterate over each image in the pdf and write that out to mongo
        pdf_images.each_with_index do |page_img, _i|
          img_tmp_file = Tempfile.new(["#{file_id}_#{_i}", '.png'])
          thumb_tmp_file = Tempfile.new(["#{file_id}_#{_i}_thumb", '.png'])
          page_img.write(img_tmp_file.path)

          _t = page_img.scale(0.25) # scale the image down to 25% of original for rendering thumbnails
          _t.write(thumb_tmp_file.path)

          if _i == 0
            _fname = 'first'
          elsif _i == pdf_images.size - 1
            _fname = 'last'
          else
            _fname = _i
          end
          _i_file_id = upload_file(img_tmp_file.path, "#{file_id}_#{_fname}.png")
          _t_file_id = upload_file(thumb_tmp_file.path, "#{file_id}_thumb_#{_fname}.png")
          sub_topic.content_slides.create(
            name: _fname,
            filename: "#{file_id}_#{_fname}.png",
            uploaded_date: DateTime.now,
            filetype: 'image/png',
            file_id: _i_file_id
          )
          sub_topic.content_thumbnails.create(
            name: _fname,
            filename: "#{file_id}_thumb_#{_fname}.png",
            uploaded_date: DateTime.now,
            filetype: 'image/png',
            file_id: _t_file_id
          )
          log "Successfully completed writing file to #{img_tmp_file.path}"
          img_tmp_file.unlink # delete the img temp file
          log "Successfully completed writing thumbnail file to #{thumb_tmp_file.path}"
          thumb_tmp_file.unlink # delete the img thumbnail file
        end
      end
    ensure
      # close the temp file and delete it
      FileUtils.rm(local_file) if File.exist?(local_file)
    end
  end

  def success
    log 'Successfully completed task'
    sub_topic.update_attributes!(lock?: false, state: 'SUCCESS')
  end

  def failure
    log 'Something went wrong'
    sub_topic.update_attributes!(lock?: false, state: 'FAILED')
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    3
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end

  # Upload's a new file using GridFS and returns id of the document
  def upload_file(file_path, file_name)
    db = nil
    begin
      db = Mongo::MongoClient.new(settings[:mongo_host], settings[:mongo_port]).db(settings[:mongo_db])
      grid = Mongo::Grid.new(db)

      # Check if a file already exists with the name specified
      files_db = db['fs.files']
      if files_db.find_one({:filename => file_name})
        return nil # File already exists
      else
        return grid.put(
            File.open(file_path),
            filename: file_name
        )
      end
    rescue
      return nil
    ensure
      db.connection.close unless db.nil?
    end
  end

  # returns a grid fs object
  def download_file(resume_id)
    db = Mongo::MongoClient.new(settings[:mongo_host], settings[:mongo_port]).db(settings[:mongo_db])
    grid = Mongo::Grid.new(db)

    # Get the file out the db
    return grid.get(BSON::ObjectId(resume_id.to_s))
    # return grid.get(resume_id)
  rescue Exception => ex
    log "Error while fetching the file from Mongo: #{ex.message}"
    log "Backtrace:\n\t#{ex.backtrace.join("\n\t")}"
    return nil
  ensure
    db.connection.close unless db.nil?
  end
end
