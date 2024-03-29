module Sync
  module Models
    # Uploaders
    require 'app/uploaders/image_uploader'
    require 'app/uploaders/resume_uploader'

    require 'app/models/reference/role'
    require 'app/models/reference/expense_category'

    Dir[File.dirname(__FILE__) + '/models/*.rb'].each { |file| require file }
  end
end