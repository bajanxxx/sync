rails_env = ENV['RAILS_ENV'] || 'development'

app_root = `pwd`.chomp
working_directory app_root
worker_processes (rails_env == 'production' ? 10 : 2)
preload_app true
timeout 30

if rails_env == 'production'
  listen "#{app_root}/tmp/sockets/unicorn.sock", :backlog => 2048
  pid "#{app_root}/tmp/pids/unicorn.pid"
  stderr_path "#{app_root}/log/unicorn.log"
  stdout_path "#{app_root}/log/unicorn.log"
else
  listen 8080
  pid "#{app_root}/tmp/pids/unicorn.pid"
  stderr_path "#{app_root}/log/unicorn.log"
  stdout_path "#{app_root}/log/unicorn.log"
end

GC.copy_on_write_friendly = true if GC.respond_to?(:copy_on_write_friendly=)

before_fork do |server, worker|
  old_pid = "#{app_root}/tmp/pids/unicorn.pid.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  worker.user('rails', 'rails') if Process.euid == 0 && rails_env == 'production'
end
