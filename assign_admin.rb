#!/usr/bin/env ruby

#
# Assigns an admin role for the specified user
#
# Usage: ./assign_admin.rb 'admin@cloudwick.com'

require 'mongoid'
require_relative 'app/models/reference/role'
require_relative 'app/models/user'
require_relative 'app/models/role'

username = ARGV[0]

if username !~ /.*@cloudwick.com/
  puts "Error: Expected cloudwick email address as the username"
  exit 1
end

Mongoid.load!(File.expand_path('config/mongoid.yml', File.dirname(__FILE__)), :development)

user = User.find_by(email: username)

if user.nil?
  puts "Error: User '#{username}' not found in the DB, tell the user to login to Sync portal atleast once."
  exit 1
end

user.create_role(name: 'administrator')
user.save!

puts "Successfully assigned administrative roles to #{username}."
exit 0