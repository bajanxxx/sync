module Sync
  module Helpers
    module Campaign
      # campaign_type could be vendors or customers
      def create_campaign(campaign_name, campaign_id)
        if campaign_exists?(campaign_id)
          Campaign.find_or_create_by(_id: campaign_id) do |campaign|
            campaign.campaign_name = campaign_name
            campaign.campaign_id = campaign_id
          end
        else
          response = RestClient.post(
              "https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/campaigns",
              name: campaign_name,
              id: campaign_id
          )
          if response.code == 200
            Campaign.find_or_create_by(_id: campaign_id) do |campaign|
              campaign.campaign_name = campaign_name
              campaign.campaign_id = campaign_id
            end
          end
        end
      end

      def delete_campaign(campaign_id)
        if campaign_exists?(campaign_id)
          RestClient.delete(
            "https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/campaigns/#{campaign_id}"
          )
        end
      end

      def campaign_exists?(campaign_id)
        exists = false
        response = RestClient.get "https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/campaigns"
        if response.code == 200
          parsed = JSON.parse(response.body, { symbolize_names: true })
          exists = true if parsed[:items].find { |ele| ele[:id] == campaign_id }
        end
        return exists
      end

      def get_campaign_stats(campaign_id)
        if campaign_exists?(campaign_id)
          response = RestClient.get("https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/campaigns/#{campaign_id}")
          data = JSON.parse(response.body, { symbolize_names: true })
          if data
            campaign = Campaign.find_by(_id: campaign_id)
            campaign.update_attributes(
              total_complained: data[:complained_count],
              total_clicked: data[:clicked_count],
              total_opened: data[:opened_count],
              total_unsubscribed: data[:unsubscribed_count],
              total_sent: data[:submitted_count],
              total_delivered: data[:delivered_count],
              total_dropped: data[:dropped_count],
              # unique_opens: data[:unique][:opened][:recipient]
            )
          end
        end
        {}
      end

      def get_campaign_sent_events
        data = []
        response =  RestClient.get("https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/stats?event=sent")
        JSON.parse(response.body, { symbolize_names: true })[:items].each do |event|
          data << [ Date.parse(event[:created_at]).strftime('%Q').to_i, event[:total_count] ]
        end
        data.sort_by{|k| k[0]}
      end

      def get_campaign_unsubscribers
        response = RestClient.get("https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/unsubscribes")
        JSON.parse(response.body, { symbolize_names: true })
      end

      def get_campaign_bounces
        response = RestClient.get("https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/#{@settings[:mailgun_domain]}/bounces")
        JSON.parse(response.body, { symbolize_names: true })
      end

      # type could be customer or vendor
      def create_route(type)
        route_name =  if type == 'customer'
                        @settings[:mailgun_customer_routes_name]
                      else
                        @settings[:mailgun_vendor_routes_name]
                      end
        match_recipient = type == 'customer' ? @settings[:mailgun_customer_email] : @settings[:mailgun_vendor_email]
        forward_emails  = type == 'customer' ? @settings[:mailgun_customer_routes_forward] : @settings[:mailgun_vendor_routes_forward]

        unless route_exists?(route_name)
          # RestClient.post("https://api:key-62-8e5xuuc0b1ojaxobl2n13mkuw4qg2@api.mailgun.net/v2/routes", priority: 0, description: 'New Route', expression: "match_recipient('jobs@mg.cloudwick.com')", action: ["forward('http://198.0.218.179/routes')"] + [ "stop()" ])
          RestClient.post(
              "https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/routes",
              priority: 0,
              description: route_name,
              expression: "match_recipient('#{match_recipient}')",
              action: [ "forward('http://#{@settings[:bind_ip]}:#{@settings[:bind_port]}/campaign/#{type}/reply')" ] + forward_emails.map{ |mail| "forward('#{mail}')" } + [ "stop()" ]
          )
        end
      end

      def route_exists?(route_name)
        exists = false
        response = RestClient.get("https://api:#{@settings[:mailgun_api_key]}@api.mailgun.net/v2/routes")
        if response.code == 200
          parsed = JSON.parse(response.body, { symbolize_names: true })
          exists = true if parsed[:items].find { |ele| ele[:description] == route_name }
        end
        exists
      end
    end
  end
end