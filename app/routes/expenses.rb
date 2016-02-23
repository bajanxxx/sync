module Sync
  module Routes
    class Expenses < Base
      %w(/expenses /expenses/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/expenses' do
        protected!

        erb :expenses, locals: {
          categories: Reference::ExpenseCategory::TYPES,
          pending_requests: ExpenseRequest.where(status: 'pending'),
          approved_requests: ExpenseRequest.where(status: 'approved'),
          disapproved_requests: ExpenseRequest.where(status: 'disapproved')
        }
      end

      post '/expenses/:eid/approve' do |eid|
        success    = true
        message    = 'Expense Request Approved.'

        er = ExpenseRequest.find(eid)
        er.update_attributes(status: 'approved', approved_by: @user.name, approved_at: DateTime.now)
        # TODO DJ for notifying user

        { success: success, msg: message }.to_json
      end

      post '/expenses/:eid/disapprove' do |eid|
        success    = true
        message    = 'Expense Request Disapproved.'

        er = ExpenseRequest.find(eid)
        er.update_attributes(status: 'disapproved', disapproved_by: @user.name, disapproved_at: DateTime.now)
        # TODO DJ for notifying user

        { success: success, msg: message }.to_json
      end

      get '/expenses/attachment/:id' do |id|
        attachment = download_file(id)
        response.headers['content_type'] = 'application/octet-stream'
        attachment(attachment.filename)
        response.write(attachment.read)
      end

      #
      # Consultant Routes
      #

      get '/expenses/:userid' do |user_id|
        self_protected!(user_id)

        erb :consultant_expenses, locals: {
          categories: Reference::ExpenseCategory::TYPES,
          pending_requests: ExpenseRequest.where(consultant_id: user_id, status: 'pending'),
          previous_requests: ExpenseRequest.where(consultant_id: user_id, :status.ne => 'pending')
        }
      end

      post '/expenses/:userid/request' do |user_id|
        success    = true
        message    = 'Successfully submitted expense request.'

        %w(expense_category amount currency).each do |param|
          if params[param.to_sym].empty?
            success = false
            message = "Param '#{param}' cannot be empty"
          end
          return { success: success, msg: message }.to_json unless success
        end

        category_id = params[:expense_category]
        amount = params[:amount]
        currency = params[:currency]
        notes = params[:notes]

        unless amount =~ /^\d{1,4}\.\d{0,2}$/
          success = false
          message = 'Amount is not properly formatted (ex: 100.00)'
          return { success: success, msg: message }.to_json unless success
        end

        if params[:receipts]
          allowed_file_types = %w(application/pdf application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document image/jpeg image/png)
          params[:receipts].keys.each do |receipt_id|
            attachment = params[:receipts][receipt_id]
            unless allowed_file_types.include?(attachment[:type])
              success = false
              message = 'Not supported file format'
              return { success: success, msg: message }.to_json unless success
            end
            unless ( File.size(attachment[:tempfile]).to_f / 2**20 ).round < 5 # 5MB
              success = false
              message = 'Attachment size exceeded'
              return { success: success, msg: message }.to_json unless success
            end
          end
        end

        if success
          categories = Reference::ExpenseCategory::TYPES

          expense = ExpenseRequest.create(
            consultant_id: user_id,
            category: categories[category_id.to_i],
            amount: Money.from_amount(amount.to_f, currency),
            currency: currency,
            notes: notes
          )

          if params[:receipts]
            params[:receipts].keys.each do |receipt_id|
              attachment = params[:receipts][receipt_id]
              file_name = "#{DateTime.now.strftime('%Q')}_#{attachment[:filename]}"
              attachment_id = upload_file(attachment[:tempfile],file_name)
              expense.expense_attachments.find_or_create_by(file_name: file_name) do |att|
                att.id = attachment_id
                att.filename = file_name
                att.uploaded_date = DateTime.now
              end
            end
          end
        end

        { success: success, msg: message }.to_json
      end
    end
  end
end
