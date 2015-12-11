module Sync
  module Routes
    class AirTickets < Base
      %w(/airtickets /airtickets/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/airtickets' do
        protected!

        file = File.read(File.expand_path("../../assets/data/us_airports.json", __FILE__))
        ap_hash = JSON.parse(file)
        erb :airtickets, locals: {
          ap_hash: ap_hash,
          pending_requests: AirTicketRequest.where(status: 'pending'),
          approved_requests: AirTicketRequest.where(status: 'approved'),
          disapproved_requests: AirTicketRequest.where(status: 'disapproved')
        }
      end

      post '/airtickets/submit' do
        cname = params[:ConsultantName]
        cemail = params[:Email]
        travel_date = params[:TravelDate]
        from_iata_code = params[:From]
        from_iata_code2 = params[:From2]
        to_iata_code = params[:To]
        to_iata_code2 = params[:To2]
        round_trip = params[:RoundTrip]
        return_date = params[:ReturnDate]
        purpose = params[:Purpose]
        flexible_from = false
        flexible_to = false
        one_way = true
        round_trip = false
        flexibility = false

        success    = true
        message    = "Air Ticket Request submitted."

        %w(ConsultantName Email TravelDate From To Purpose).each do |param|
          if params[param.to_sym].empty?
            success = false
            message = "Param '#{param}' cannot be empty"
          end
          return { success: success, msg: message }.to_json unless success
        end

        if params.key?("FlexibleFrom")
          flexible_from = true
          if params[:From2].empty?
            success = false
            message = "Param 'flexible_from' cannot be empty"
            return { success: success, msg: message }.to_json
          end
        end

        if params.key?("FlexibleTo")
          flexible_to = true
          if params[:To2].empty?
            success = false
            message = "Param 'flexible_to' cannot be empty"
            return { success: success, msg: message }.to_json
          end
        end

        if params.key?("RoundTrip")
          round_trip = true
          one_way = false
          if params[:ReturnDate].empty?
            success = false
            message = "Param 'return_date' cannot be empty"
            return { success: success, msg: message }.to_json
          end
        else
          one_way = true
        end

        if params.key?("Flexibility")
          flexibility = true
        end

        if success
          # process the request
          ar =  AirTicketRequest.create(
              consultant_name: cname,
              consultant_email: cemail,
              travel_date: travel_date,
              purpose: purpose,
              from_apc: from_iata_code,
              flexible_from: flexible_from,
              from_apc2: from_iata_code2,
              to_apc: to_iata_code,
              flexible_to: flexible_to,
              to_apc2: to_iata_code2,
              one_way: one_way,
              round_trip: round_trip,
              return_date: return_date,
              flexibility: flexibility,
              admin_created: true
          )
        end

        { success: success, msg: message }.to_json
      end

      post '/airtickets/approve/:rid' do |rid|
        success    = true
        message    = "Air Ticket Request Approved."

        # check for amount
        amount = params[:amount]

        unless amount =~ /^\d{1,4}\.\d{0,2}$/
          success = false
          message = "Amount is not properly formatted"
        end

        if success
          ar = AirTicketRequest.find(rid)
          ar.update_attributes(status: 'approved', approved_by: @user.name, approved_at: DateTime.now, amount: amount)
          Delayed::Job.enqueue(
              EmailRequestStatus.new(@settings, @user.name, ar, "AirTicket (from: #{ar.from_apc} -> to: #{ar.to_apc})"),
              queue: 'consultant_airticket_requests',
              priority: 10,
              run_at: 1.seconds.from_now
          )
        end

        { success: success, msg: message }.to_json
      end

      post '/airtickets/deny/:rid' do |rid|
        ar = AirTicketRequest.find(rid)
        ar.update_attributes(status: 'disapproved', disapproved_by: @user.name, disapproved_at: DateTime.now)
        Delayed::Job.enqueue(
            EmailRequestStatus.new(@settings, @user.name, ar, "AirTicket (from: #{ar.from_apc} -> to: #{ar.to_apc})"),
            queue: 'consultant_airticket_requests',
            priority: 10,
            run_at: 1.seconds.from_now
        )

        flash[:info] = 'Sucessfully disapproved and updated the user status of the request'
        redirect "/airtickets"
      end

      #
      # => AirTicket Requests (Consultant Routes)
      #

      get '/airtickets/:userid' do |userid|
        self_protected!(userid)

        file = File.read(File.expand_path("../../assets/data/us_airports.json", __FILE__))
        ap_hash = JSON.parse(file)

        erb :consultant_airtickets, locals: {
            ap_hash: ap_hash,
            consultant: Consultant.find_by(email: userid),
            pending_requests: AirTicketRequest.where(consultant_email: userid, status: 'pending'),
            previous_requests: AirTicketRequest.where(consultant_email: userid, :status.ne => 'pending')
        }
      end

      post '/airtickets/:userid/request' do |userid|
        cfname = params[:firstname]
        clname = params[:lastname]
        cpnum = params[:phonenum]
        cdob = params[:dob]
        from_apc = params[:from]
        from_apc2 = params[:from2]
        to_apc = params[:to]
        to_apc2 = params[:to2]
        travel_date = params[:traveldate]
        flexible_from = false
        flexible_to = false
        one_way = false
        round_trip = false
        return_date = params[:returndate]
        flexibility = false
        purpose = params[:purpose]

        success    = true
        message    = "Air Ticket Request submitted."

        %w(firstname lastname phonenum dob from to traveldate purpose).each do |param|
          if params[param.to_sym].empty?
            success = false
            message = "Field '#{param}' cannot be empty"
          end
          return { success: success, msg: message }.to_json unless success
        end

        if params.key?("flexiblefrom")
          flexible_from = true
          if params[:from2].empty?
            success = false
            message = "Param 'flexible_from' cannot be empty"
            return { success: success, msg: message }.to_json
          end
        end

        if params.key?("flexibleto")
          flexible_to = true
          if params[:to2].empty?
            success = false
            message = "Param 'flexible_to' cannot be empty"
            return { success: success, msg: message }.to_json
          end
        end

        if params.key?("roundtrip")
          round_trip = true
          one_way = false
          if params[:returndate].empty?
            success = false
            message = "Param 'return_date' cannot be empty"
            return { success: success, msg: message }.to_json
          end
        else
          one_way = true
        end

        if params.key?("flexibility")
          flexibility = true
        end

        if success
          # process the request
          ar =  AirTicketRequest.create(
              consultant_first_name: cfname,
              consultant_last_name: clname,
              consultant_dob: cdob,
              consultant_phone: cpnum,
              consultant_email: userid,
              travel_date: travel_date,
              purpose: purpose,
              from_apc: from_apc,
              flexible_from: flexible_from,
              from_apc2: from_apc2,
              to_apc: to_apc,
              flexible_to: flexible_to,
              to_apc2: to_apc2,
              one_way: one_way,
              round_trip: round_trip,
              return_date: return_date,
              flexibility: flexibility
          )
          # Send email to the admin group
          Delayed::Job.enqueue(
              EmailAirTicketRequest.new(@settings, @user.name, ar),
              queue: 'consultant_airticket_requests',
              priority: 10,
              run_at: 1.seconds.from_now
          )
          # Send an sms to the admin
          @settings[:admin_phone].each do |to_phone|
            twilio.account.messages.create(
                from: @settings[:twilio_phone],
                to: to_phone,
                body: "SYNC: #{cfname} #{clname} air ticket booking"
            )
          end
        end

        { success: success, msg: message }.to_json
      end

    end
  end
end