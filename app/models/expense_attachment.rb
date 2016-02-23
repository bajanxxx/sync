class ExpenseAttachment
  include Mongoid::Document

  field :filename, type: String
  field :uploaded_date, type: String
  field :_id, type: String

  belongs_to :expense_request, class_name: 'ExpenseRequest'
end
