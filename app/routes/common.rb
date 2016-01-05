module Sync
  module Routes
    class Common < Base
      get '/download/:id' do |id|
        protected!

        file = download_file(id)
        response.headers['content_type'] = 'application/octet-stream'
        attachment(file.filename)
        response.write(file.read)
      end
    end
  end
end
