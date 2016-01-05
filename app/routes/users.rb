module Sync
  module Routes
    class Users < Base
      get '/login' do
        if session_username
          redirect back
        else
          erb :login, :locals => {:login_error => ''}
        end
      end

      get '/auth/failure' do
        content_type 'text/plain'
        request.env['omniauth.auth'].to_hash.inspect rescue 'No Data'
      end

      get '/auth/:provider/callback' do
        auth = env['omniauth.auth']
        if auth.info['email'].split('@')[1] == 'cloudwick.com'
          # signed in as cloudwick user, create a session for the user
          user_email = auth.info['email']
          session_uid = auth['uid']
          google_profile = auth.info.urls && auth.info.urls['Google'] || nil

          # make sure user exists in the user collection
          User.find_or_create_by(
              email: user_email
          ).update_attributes(
              first_name: auth.info['first_name'],
              last_name: auth.info['last_name'],
              image_url: auth.info['image'],
              google_profile: google_profile
          )

          # create/update consultant document
          Consultant.find_or_create_by(
            email: user_email
          ).update_attributes(
              first_name: auth.info['first_name'],
              last_name: auth.info['last_name'],
          )

          # create a detail collection for the user
          Detail.find_or_create_by(consultant_id: user_email)

          # create a session for the user in the collection
          session_id = start_session(user_email, session_uid)
          redirect '/internal_error' unless session_id
          # set the cookie
          session[:uid] = session_uid
          session[:email] = user_email
        else
          halt erb(:login, :locals => {:login_error => 'cloudwick_email'})
        end
        # this is the main endpoint to your application
        redirect to('/')
      end

      get '/logout' do
        end_session
        session.clear # clear the session cookie
        flash[:info] = 'You are successfully logged out. Thanks for visiting!'
        redirect '/'
      end

      # user management - assign user's roles like trainer, trainee, consultant
      get '/users' do
        erb :users, locals: { users: User.asc(:email) }
      end

      get '/users/roles' do
        status_values = []
        Reference::Role::TYPES.each do |name|
          next if name == :owner || name == :administrator
          status_values << { text: "#{name}", value: "#{name}" }
        end
        if @user.owner?
          status_values << {text: 'administrator', value: 'administrator'}
        end
        if request.xhr?
          halt 200, status_values.to_json
        else
          status_values.to_json
        end
      end

      post '/users/:id/role' do |user_id|
        success = true
        message = 'Successfully updated role of the user'

        user = User.find(user_id)
        if user.role?
          user.role.update_attribute(:name, params[:value])
        else
          user.create_role(name: params[:value])
        end

        { success: success, msg: message }.to_json
      end
    end
  end
end