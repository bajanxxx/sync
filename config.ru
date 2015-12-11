require './app'

environment = ENV["RACK_ENV"]

log = File.new(File.expand_path("../log/#{environment}.log", __FILE__), 'a+')

$stdout.reopen(log)
$stdout.sync = true
$stderr.reopen(log)
$stderr.sync = true

run Sync::App
