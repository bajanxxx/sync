class ExpenseRequest
  include Mongoid::Document

  field :consultant_id, type: String
  field :category, type: String
  field :amount, type: Money
  field :currency, type: String, default: 'USD'
  field :created_at, type: DateTime, default: DateTime.now
  field :status, type: String, default: 'pending' # approved | rejected | pending
  field :approved_by, type: String # who approved the request
  field :approved_at, type: DateTime
  field :disapproved_by, type: String
  field :disapproved_at, type: DateTime
  field :admin_created, type: Boolean, default: false

  has_many :expense_attachments, class_name: 'ExpenseAttachment'
end

Money.class_eval do
  # Converts an object of this instance into a database friendly value.
  def mongoize
    [cents, currency.to_s]
  end

  class << self

    # Get the object as it was stored in the database, and instantiate
    # this custom class from it.
    def demongoize(object)
      cur = object[1] || Money.default_currency
      Money.new(object[0], cur)
    end

    # Takes any possible object and converts it to how it would be
    # stored in the database.
    def mongoize(object)
      case object
        when Money
          object.mongoize
        else object
      end
    end

    # Converts the object that was supplied to a criteria and converts it
    # into a database friendly form.
    def evolve(object)
      case object
        when Money then object.mongoize
        else object
      end
    end
  end

end