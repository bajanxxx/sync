=begin
Verifies if all job postings (3 days older) are still reachable (alive)
=end
require 'net/http'
require 'open-uri'
require 'pp'
require 'pathname'
require 'optparse'
require 'ostruct'
require 'mongoid'
require 'parallel'

require_relative 'models/job'
require_relative 'models/application'

# Checks if a url exists (reachable)
def url_exist?(url)
  uri       = URI.parse(url)
  response  = Net::HTTP.get_response(uri)
  if response.code == '301' || response.code == '302'
    return false
  end
  return true
rescue Errno::ENOENT # 404
  return false
end

puts "Initializing validator @ #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

Mongoid.load!(File.expand_path('./mongoid.yml', File.dirname(__FILE__)), :development)

mutex = Mutex.new
unavailable = Array.new
Parallel.each(
  Job.where(:date_posted.lt => (Date.today - 3).strftime("%Y-%m-%d"),
  link_active: true), :in_threads => 50) do |rs|
    mutex.synchronize { unavailable << rs } unless url_exist?(rs.url)
end

unavailable.each do |unavailable_jobs|
  unavailable_jobs.link_active = false
  unavailable_jobs.save
end

puts "Total processed|updated: #{unavailable.length}"
