module Sync
  module Helpers
    module GridFs
      def db
        Mongo::MongoClient.new(@settings[:mongo_host], @settings[:mongo_port]).db(@settings[:mongo_db])
      end

      def grid
        Mongo::Grid.new(db)
      end

      # Upload's a new file using GridFS and returns id of the document
      def upload_file(file_path, file_name)
        db = nil
        begin
          db = Mongo::MongoClient.new(@settings[:mongo_host], @settings[:mongo_port]).db(@settings[:mongo_db])
          grid = Mongo::Grid.new(db)

          # Check if a file already exists with the name specified
          files_db = db['fs.files']
          if files_db.find_one({:filename => file_name})
            return nil # File already exists
          else
            return grid.put(
                File.open(file_path),
                filename: file_name,
            # content_type: file_type,
            # metadata: { 'description' => description }
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
        db = Mongo::MongoClient.new(@settings[:mongo_host], @settings[:mongo_port]).db(@settings[:mongo_db])
        grid = Mongo::Grid.new(db)

        # Get the file out the db
        return grid.get(BSON::ObjectId(resume_id))
          # return grid.get(resume_id)
      rescue Exception => ex
        p ex
        return nil
      ensure
        db.connection.close unless db.nil?
      end
    end
  end
end