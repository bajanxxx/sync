module Sync
  module Routes
    class TimesheetClients < Base
      post '/timesheets/manage/client' do
        success    = true
        message    = 'Successfully created vendor'

        name = params[:ClientName]
        address = params[:ClientAddress]
        preferred_currency = params[:PreferredClientCurrency]

        if name.empty? || address.empty? || preferred_currency.empty?
          success = false
          message = 'fields cannot be empty'
        else
          TimeClient.create(name: name, address: address, preferred_currency: preferred_currency)
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/manage/client/:cid/update' do |cid|
        success = true
        message = 'Successfully updated client details'

        name = params[:name]
        address = params[:address]
        currency = params[:currency]

        if name.empty? || address.empty? || currency.empty?
          success = false
          message = 'fields cannot be empty'
        else
          TimeClient.find(cid).update_attributes(
            name: name,
            address: address,
            preferred_currency: currency
          )
        end

        { success: success, msg: message }.to_json
      end
    end
  end
end
