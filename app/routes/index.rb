module Sync
  module Routes
    class Index < Base
      get '/' do
        if session_username # if the user has a login session associated
          if @user.role? # does the user has role associated?
            if @user.owner? || @user.administrator?
              # get fetcher stats
              fetcher_stats = Fetcher.where(:init_time.gt => (Date.today-30))
              fetcher_data = []
              fetcher_stats.map do |fetcher|
                fetcher_data << [ fetcher.init_time.to_datetime.to_i * 1000, fetcher.jobs_processed ]
              end
              # get requests counts in last 30 days
              certification_requests = CertificationRequest.where(:created_at.gt => (Date.today - 30))
              document_requests = DocumentRequest.where(:created_at.gt => (Date.today - 30))
              air_ticket_requests = AirTicketRequest.where(:created_at.gt => (Date.today - 30))
              erb :admin_home, locals: {
                  fetcher_data: fetcher_data.sort_by{|k| k[0]},
                  certification_requests: certification_requests,
                  document_requests: document_requests,
                  air_ticket_requests: air_ticket_requests
              }
            # elsif @user.consultant?
            else
              redirect "/consultant/#{session_username}"
            end
          else
            erb :index_norole
          end
        else
          erb :index
        end
      end

      get '/consultant/:user' do |user|
        erb :consultant_home, locals: { user: user }
      end

      get '/boom' do
        raise 'Boom!'
      end
    end
  end
end