require_relative './session'
# Sessions will be managed in mongodb
class SessionDAO
  def self.get_session(session_id)
    Session.find_by(session_id: session_id)
  rescue Mongoid::Errors::DocumentNotFound
    nil
  end

  # start a new session id by adding a new document to the sessions collections
  # returns the sessionID or nil
  def self.start_session(username)
    session_id = rand(36**32).to_s(36) # random string of length 32
    begin
      Session.create(session_id: session_id, username: username)
    rescue
      puts "Unexpected error on start_session: #{$!}"
      return nil
    end
    return session_id.to_s
  end

  # send a new user session by deleteing from sessions table
  def self.end_session(session_id)
    session = get_session(session_id)
    session.delete if session
  end

  # get the username of the current session, or nil if the session is not valid
  def self.get_username(session_id)
    session = get_session(session_id)
    if session
      session.username
    else
      nil
    end
  end
end
