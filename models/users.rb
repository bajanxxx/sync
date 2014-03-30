require 'digest'

class UserDAO
  SECRET = 'verysecret'

  def initialize(db)
    @db = db
    @users = db["users"]
  end

  # makes a little salt of 5 chars long
  def make_salt
    rand(26**5).to_s(26)
  end

  # implement the function make_pw_hash(name, pw) that returns a hashed
  # password of the format:
  # HASH(pw + salt),salt
  # use sha256
  def make_pw_hash(pwd, salt=nil)
    salt = make_salt unless salt
    Digest::SHA256.hexdigest(pwd + salt) + "," + salt
  end

  # validate a user login, return user record or nil
  def validate_login(username, password)
    user = nil
    begin
      user = @users.find_one({'_id' => username})
    rescue
      puts "Unable to query the database for user"
    end

    if ! user
      puts "User not in database"
      return nil
    end

    salt = user['password'].split(',')[1]
    if user['password'] != make_pw_hash(password, salt)
      puts "user password is not a match"
      return nil
    end

    # looks good
    return user
  end

  # create a new user in the users collection
  def add_user(username, password)
    password_hash = make_pw_hash(password)

    user = {'_id' => username, 'password' => password_hash}

    begin
      @users.insert(user)
    rescue Mongo::OperationFailure => e
      if e.message =~ /^11000/
        puts "[Error]: Duplicate key error #{$!}"
        return false
      else
        puts "[Error]: oops, mongo error, #{$!}"
        return false
      end
    end
    return true
  end
end
