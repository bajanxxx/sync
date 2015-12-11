class User
  include Mongoid::Document

  field :email,           type: String
  field :first_name,      type: String
  field :last_name,       type: String
  field :image_url,       type: String
  field :google_profile,  type: String
  field :_id,             type: String, default: ->{ email }

  field :lun,             type: String   # linux username
  field :lpwd,            type: String   # linux password
  field :pem,             type: String   # linux ssh private key
  field :pub,             type: String   # linux ssh public key
  field :fin,             type: String   # linux ssh fingerprint

  # validates :first_name, :last_name, presence: true

  embeds_one :role, validate: false

  index({'role.name' => 1 }, {background: true })
  index({'role.role_id' => 1 }, {background: true })

  # Convenience methods for determining if the user itself is of a specific
  # role in the application.
  #
  # @example Is the user an admin?
  #   user.administrator?
  #
  # @example Is the user an artist?
  #   user.consultant?
  #
  # @example Is the user a producer?
  #   user.trainer?
  #
  # @example Is the user a subscriber?
  #   user.trainee?
  #
  # @return [ true, false ] If the user is of the expected type.
  delegate \
    :administrator?,
    :consultant?,
    :trainer?,
    :trainee?, to: :role

  Reference::Role::TYPES.each do |name|
    # Get all the users for the application for this role.
    #
    # @example Get the administrators.
    #   User.administrators
    #
    # @example Get the artists.
    #   User.consultants
    #
    # @example Get the producers.
    #   User.trainers
    #
    # @example Get the subscribers.
    #   User.trainees
    #
    # @return [ Array<User> ] The matching users.
    scope "#{name}s", ->{ where("role.name" => name.to_s) }
  end

  # Does the user have the ability to perform the supplied action?
  #
  # @example Can the user act?
  #   user.able_to?("manage.users")
  #
  # @param [ String ] action The action to check.
  #
  # @return [ true, false ] If the user can act.
  def able_to?(action)
    role.able_to?(action, self)
  end

  # Gets the name of this user. If a handle was provided it uses that,
  # otherwise returns the first and last names.
  #
  # @example Get the user's name.
  #   user.name
  #
  # @return [ String ] The user name.
  def name
    "#{first_name} #{last_name}".strip
  end
end
