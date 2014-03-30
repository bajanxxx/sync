# Sessions will be managed in mongodb
class SessionDAO
  attr_accessor :db, :sessions

  def initialize(database)
    @db = database
    @sessions = database["sessions"]
  end

  # start a new session id by adding a new document to the sessions collections
  # returns the sessionID or nil
  def start_session(username)
    session_id = rand(36**32).to_s(36) # random string of length 32
    session = {'username' => username, '_id' => session_id}
    begin
      # 'save' is safer than insert, if the document already has an '_id' key,
      # then an update (upsert) operation will be performed, and any existing
      # document with that _id is overwritten. Otherwise an insert operation is
      # performed.
      @sessions.save(session)
    rescue
      puts "Unexpected error on start_session: #{$!}"
      return nil
    end
    return session['_id'].to_s
  end

  # send a new user session by deleteing from sessions table
  def end_session(session_id)
    @sessions.remove({'_id' => session_id}) if session_id
  end

  # if there is a valid session, it is returned
  def get_session(session_id)
    if session_id
      @sessions.find_one({'_id' => session_id})
    else
      nil
    end
  end

  # get the username of the current session, or nil if the session is not valid
  def get_username(session_id)
    session = get_session(session_id)
    if session
      session['username']
    else
      nil
    end
  end
end
