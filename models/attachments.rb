class AttachementsDAO
  attr_accessor :db, :attachments

  def initialize(database)
    @db = database
    @attachements = database['attachement']
  end

  def insert_attachment(aid, file, last_updated, mid)
    attachment = {
      '_id' => aid,
      'file' => file,
      'last_updated' => last_updated,
      'mid' => mid
    }

    begin
      @attachments.insert(attachment)
    rescue
      puts "Error inserting attachment"
      puts "Unexpected Error: #{$!}"
    end
  end
end
