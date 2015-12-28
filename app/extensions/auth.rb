module Sync
  module Extensions
    module Auth extend self
      module Helpers
        def current_user_from_session
          user_id = session[:user_id]
          user_id && User[user_id]
        end

        def current_user=(user)
          session[:user_id] = user && user.id
        end

        def current_user
          @current_user ||= current_user_from_session
        end

        def current_user?
          !!current_user
        end

        def get_session
          Session.find_by(session_id: session[:uid])
        rescue Mongoid::Errors::DocumentNotFound
          nil
        end

        def start_session(user_id, session_id)
          session = Session.find_or_create_by(session_id: session_id, username: user_id)
          session.update_attribute(:active, true)
        rescue
          nil
        end

        def end_session
          session = get_session
          if session && session.active
            session.update_attribute(:active, false)
          end
        end

        def session_username
          session = get_session
          if session && session.active
            session.username
          else
            nil
          end
        end

        # use this method in the route whenever admin access is required
        def protected!
          user = User.find(session_username) if session_username
          halt 401, 'You are not authorized to see this page!. This action will be reported.' unless user.owner? || user.administrator?
        end

        # use this method in the route whenever only admin and loggedin user can access
        def self_protected!(username)
          user = User.find(session_username) if session_username
          unless (user.administrator? || user.owner?) or user.email == username
            halt 401, 'You are not authorized to see this page!. This action will be reported.'
          end
        end
      end

      def registered(app)
        app.helpers Helpers
      end
    end
  end
end