require 'digest'
require_relative './user'

class UserDAO
  SECRET = 'verysecret'

  # makes a little salt of 5 chars long
  def self.make_salt
    rand(26**5).to_s(26)
  end

  # implement the function make_pw_hash(name, pw) that returns a hashed
  # password of the format:
  # HASH(pw + salt),salt
  # use sha256
  def self.make_pw_hash(pwd, salt=nil)
    salt = make_salt unless salt
    Digest::SHA256.hexdigest(pwd + salt) + "," + salt
  end

  def self.find_user(username)
    User.find_by(_id: username)
  rescue Mongoid::Errors::DocumentNotFound
    nil
  end

  # validate a user login, return user record or nil
  def self.validate_login(username, password)
    user = find_user(username)

    if !user
      puts "User not in database"
      return nil
    end

    salt = user.password.split(',')[1]
    if user.password != make_pw_hash(password, salt)
      puts "user password is not a match"
      return nil
    end

    # looks good
    return user
  end

  # create a new user in the users collection
  def self.add_user(username, password)
    password_hash = make_pw_hash(password)
    user = find_user(username)

    if !user
      if User.where(:admin => true).count > 0
        User.create!(email: username, password: password_hash)
      else
        User.create!(email: username, password: password_hash, admin: true)
      end
      return true
    else
      return false
    end
  end
end
