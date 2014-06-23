# Simple task runs using delayed_job
class SimpleTask
  def doit
    say "just did something simple!"
  end
  handle_asynchronously :doit

  def doit_in_5secs
    say "returning back after 5 seconds"
  end
  handle_asynchronously :doit_in_5secs, :run_at => Proc.new { 5.seconds.from_now }

  def say(text)
    Delayed::Worker.logger.add(Logger::INFO, text)
  end
end
