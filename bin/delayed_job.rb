#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'app'))
require 'delayed/command'

Delayed::Command.new(ARGV).daemonize
