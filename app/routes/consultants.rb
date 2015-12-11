module Sync
  module Routes
    class Consultants < Base
      %w(/consultants /consultants/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/consultants' do
        protected!
        erb :consultants, locals: { consultants: Consultant.asc(:first_name) }
      end

      get '/consultant/:id/info' do |consultant_id|
        protected!
        erb :consultant_info, locals: {
          consultant: Consultant.find(consultant_id),
          details: Detail.find_by(consultant_id: consultant_id)
        }
      end

      post '/consultant/info/update' do
        consultant_id = params[:pk]
        update_key    = params[:name]
        update_value  = params[:value]
        success       = true
        message       = "Successfully updated #{update_key} to #{update_value}"
        # Find the consultant by id
        consultant = Consultant.find(consultant_id)
        if consultant.nil?
          success = false
          message = "Cannot find user specified by #{consultant_id}"
        end
        # Update the consultant parameters
        begin
          case update_key
            when 'domain'
              consultant.update_attribute(update_key.to_sym, update_value.first)
            else
              consultant.update_attribute(update_key.to_sym, update_value)
          end
        rescue
          success = false
          message = "Failed to update(#{update_key})"
        end
        # Return json response to be validated on the client side
        { success: success, msg: message }.to_json
      end

      post '/consultant/info/details/update' do
        consultant_id = params[:pk]
        update_key = params[:name]
        update_value = params[:value]
        success = true
        message = "Successfully updated #{update_key} to #{update_value}"

        begin
          case update_key
            when 'training_tracks'
              update_value = [] if update_value.nil?
              Detail.find_by(consultant_id: consultant_id).update_attribute(update_key.to_sym, update_value)
            when 'certifications'
              update_value = [] if update_value.nil?
              Detail.find_by(consultant_id: consultant_id).update_attribute(update_key.to_sym, update_value)
            else
              Detail.find_by(consultant_id: consultant_id).update_attribute(update_key.to_sym, update_value)
          end

        rescue
          success = false
          message = "Failed to update(#{update_key})"
        end
        # Return json response to be validated on the client side
        { success: success, msg: message }.to_json
      end

      get '/consultant/details/certifications/possible_values' do
        status_values = []
        file = File.read(File.expand_path("../../assets/data/certifications.json", __FILE__))
        c_hash = JSON.parse(file)
        c_hash.each do |c|
          status_values << { text: "#{c['name']}", value: "#{c['short']}" }
        end

        if request.xhr?
          halt 200, status_values.to_json
        else
          status_values.to_json
        end
      end

      get '/consultant/details/training_tracks/possible_values' do
        status_values = []
        tracks = TrainingTrack.all
        tracks.each do |track|
          status_values << { text: "#{track.name}", value: "#{track.code}" }
        end

        if request.xhr?
          halt 200, status_values.to_json
        else
          status_values.to_json
        end
      end

      get '/consultant/details/domains/possible_values' do
        [
            { text: "US", value: "US" },
            { text: "EU", value: "EU" },
            { text: "IN", value: "IN" }
        ].to_json
      end
    end
  end
end