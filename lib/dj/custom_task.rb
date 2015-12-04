# Usage: Delayed::Job.enqueue CustomTask.new('lorem ipsum...')
class CustomTask < Struct.new(:text)
  def perform
    say "Performing simple task of printing out #{text}"
  end

  def success
    say "successfully completed task"
  end

  def failure
    say "something went wrong notify someone"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    3
  end

  def say(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
