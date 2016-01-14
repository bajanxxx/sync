#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'app'))
require 'delayed/command'

Delayed::Worker.destroy_failed_jobs = false

Delayed::Command.new(ARGV).daemonize
