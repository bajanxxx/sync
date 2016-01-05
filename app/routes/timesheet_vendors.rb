module Sync
  module Routes
    class TimesheetVendors < Base
      post '/timesheets/manage/vendor' do
        success    = true
        message    = 'Successfully created vendor'

        name = params[:VendorName]
        address = params[:Address]
        preferred_currency = params[:PreferredCurrency]

        if name.empty? || address.empty? || preferred_currency.empty?
          success = false
          message = 'fields cannot be empty'
        else
          TimeVendor.create(name: name, address: address, preferred_currency: preferred_currency)
        end

        { success: success, msg: message }.to_json
      end

      post '/timesheets/manage/vendor/:vid/update' do |vid|
        success = true
        message = 'Successfully updated vendor details'

        name = params[:name]
        address = params[:address]
        currency = params[:currency]

        if name.empty? || address.empty? || currency.empty?
          success = false
          message = 'fields cannot be empty'
        else
          TimeVendor.find(vid).update_attributes(
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
