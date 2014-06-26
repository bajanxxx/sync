class FetchDicePostings < Struct.new(:base_url, :search_string, :age, :pages_to_traverse, :page_saerch)
  @@processed_data = Hash.new
  @@mutex = Mutex.new
  @@processed = 0
  
  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end

class Test
  @@sides = 10

  def call
    @@sides
  end
end
