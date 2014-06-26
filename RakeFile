require 'rake'

task :environment do
  require_relative 'app'
end

namespace :mongoid_search do
  desc 'Goes through all documents with search enabled and indexes the keywords.'
  task :index => :environment do
    if Mongoid::Search.classes.blank?
      Mongoid::Search::Log.log "No model to index keywords.\n"
    else
      Mongoid::Search.classes.each do |klass|
        Mongoid::Search::Log.silent = ENV['SILENT']
        Mongoid::Search::Log.log "\nIndexing documents for #{klass.name}:\n"
        klass.index_keywords!
      end
      Mongoid::Search::Log.log "\n\nDone.\n"
    end
  end
end

namespace :mongoid do
  desc 'Create indexes for job collection in mongo'
  task :create_job_indexes => :environment do
    Mongoid.load!("config/mongoid.yml", :development)
    Job.create_indexes
  end

  desc 'Create indexes for customers collection in mongo'
  task :create_customer_indexes => :environment do
    Mongoid.load!("config/mongoid.yml", :development)
    Customer.create_indexes
  end

  desc 'Create indexes for vendors collection in mongo'
  task :create_vendor_indexes => :environment do
    Mongoid.load!("config/mongoid.yml", :development)
    Vendor.create_indexes
  end

  desc 'Create indexes for tracking collection in monog'
  task :create_tracking_indexes => :environment do
    Mongoid.load!("config/mongoid.yml", :development)
    Tracking.create_indexes
  end
end

namespace :jobs do
  desc "Clear the delayed_job queue."
  task :clear => :environment do
    Delayed::Job.delete_all
  end

  desc 'delayed_job create indexes'
  task :create_indexes => :environment do
    Delayed::Backend::Mongoid::Job.create_indexes
  end

  desc 'delayed_job worker process'
  task :work => :environment do
    Delayed::Worker.new(:min_priority => ENV['MIN_PRIORITY'], :max_priority => ENV['MAX_PRIORITY']).start
  end
end
