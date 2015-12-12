module Sync
  module Routes
    class CloudServers < Base
      %w(/cloudservers /cloudservers/*).each do |path|
        before path do
          redirect '/login' unless @session_username
        end
      end

      get '/cloudservers' do
        protected!

        openstack_capacity = {}

        conn = create_openstack_connection
        if conn
          user_limits = conn.get_limits
          openstack_capacity[:current_instances] = user_limits.body['limits']['absolute']['totalInstancesUsed']
          openstack_capacity[:max_instances]     = user_limits.body['limits']['absolute']['maxTotalInstances']
          openstack_capacity[:max_cores]         = user_limits.body['limits']['absolute']['maxTotalCores']
          openstack_capacity[:current_cores]     = user_limits.body['limits']['absolute']['totalCoresUsed']
          openstack_capacity[:max_ram]           = user_limits.body['limits']['absolute']['maxTotalRAMSize']
          openstack_capacity[:current_ram]       = user_limits.body['limits']['absolute']['totalRAMUsed']
          openstack_capacity[:current_secgroups] = user_limits.body['limits']['absolute']['totalSecurityGroupsUsed']
          openstack_capacity[:max_secgroups]     = user_limits.body['limits']['absolute']['maxSecurityGroups']
        end
        erb :cloudservers, locals: { oc: openstack_capacity }
      end

      get '/cloudservers/requests' do
        protected!

        erb :cloudserver_requests, locals: {
            consultant: Consultant.find_by(email: @session_username),
            images: CloudImage.all,
            flavors: CloudFlavor.all,
            pending_requests: CloudRequest.where(approved?: false, disapproved?: false),
            bootstrapping_requests: CloudRequest.where(approved?: true, fulfilled?: false, connection_failed?: false),
            failed_requests: CloudRequest.where(approved?: true, fulfilled?: false, connection_failed?: true),
            running_requests: CloudRequest.where(approved?: true, fulfilled?: true, active?: true)
        }
      end

      get '/cloudservers/requests/:userid' do |userid|
        self_protected!(userid)

        erb :consultant_cloudservers, locals: {
            consultant: Consultant.find_by(email: userid),
            images: CloudImage.all,
            flavors: CloudFlavor.all,
            pending_requests: CloudRequest.where(requester: userid, approved?: false, disapproved?: false),
            bootstrapping_requests: CloudRequest.where(requester: userid, approved?: true, fulfilled?: false),
            running_requests: CloudRequest.where(requester: userid, approved?: true, fulfilled?: true, active?: true)
        }
      end

      post '/cloudservers/requests/deny/:id' do |rid|
        dr = CloudRequest.find(rid)
        dr.update_attributes(disapproved?: true, disapproved_by: @user.name, disapproved_at: DateTime.now)
        # TODO: write a delayed job
        # Delayed::Job.enqueue(
        #   EmailRequestStatus.new(@settings, @user.name, dr),
        #   queue: 'consultant_document_requests',
        #   priority: 10,
        #   run_at: 1.seconds.from_now
        # )
        # Delete all the created requests associated with the user
        dr.cloud_instances.delete_all
        flash[:info] = 'Successfully disapproved and updated the user status of the request'
        redirect '/cloudservers/requests'
      end

      post '/cloudservers/requests/approve/:id' do |rid|
        cr = CloudRequest.find(rid)
        cr.update_attributes(approved?: true, approved_by: @user.name, approved_at: DateTime.now)

        Delayed::Job.enqueue(
            CreateCloudInstances.new(@settings, cr, User.find_by(email: cr.requester)),
            queue: 'create_cloud_servers',
            priority: 10
        )

        flash[:info] = 'Successfully approved and scheduled the servers to bootstrap'
        redirect '/cloudservers/requests'
      end

      post '/cloudservers/requests/retry/:id' do |rid|
        cr = CloudRequest.find(rid)
        cr.update_attributes!(connection_failed?: false)

        Delayed::Job.enqueue(
            CreateCloudInstances.new(@settings, cr, User.find_by(email: cr.requester)),
            queue: 'create_cloud_servers',
            priority: 10
        )

        flash[:info] = 'Successfully scheduled the servers to bootstrap (retry)'
        redirect '/cloudservers/requests'
      end

      post '/cloudservers/requests/delete/:id' do |rid|
        success = true
        message = 'Successfully scheduled instance(s) to be deleted'

        cr = CloudRequest.find(rid)

        Delayed::Job.enqueue(
            DeleteCloudInstances.new(@settings, cr, User.find_by(email: cr.requester)),
            queue: 'delete_cloud_servers',
            priority: 10
        )

        flash[:info] = 'Successfully scheduled the servers to delete'

        { success: success, msg: message }.to_json
      end

      post '/cloudservers/:id/requests' do |consultant_id|
        # ap params
        success    = true
        message    = 'Successfully created a requests'

        # {"NumberOfInstances"=>"1", "InstanceType"=>"1", "Image"=>"566b97d7-2ee9-4c1a-bc51-c25424215f7f", "DomainName"=>"", "Purpose"=>"", "splat"=>[], "captures"=>["ashrith@cloudwick.com"], "id"=>"ashrith@cloudwick.com"}
        number_of_instances = params[:NumberOfInstances]
        flavor_id = params[:InstanceType]
        image_id = params[:Image]
        server_name = params[:ServerName] || consultant_id.split('@').first.gsub('.', '_')
        domain_name = params[:DomainName] || 'ankus.cloudwick.com'
        purpose = params[:Purpose]

        req = CloudRequest.create(requester: consultant_id, purpose: purpose)
        flavor = CloudFlavor.find(flavor_id)

        number_of_instances.to_i.times do |i|
          os_type = CloudImage.find(image_id).os
          req.cloud_instances << CloudInstance.new(
              user_id: consultant_id,
              instance_name: "#{server_name}#{i+1}.#{domain_name}",
              flavor_id: flavor_id,
              image_id: image_id,
              os_flavor: os_type.downcase,
              vcpus: flavor.vcpus,
              mem: flavor.mem,
              disk: flavor.disk
          )
        end

        # TODO: Write a delayed_job to send email alerts

        { success: success, msg: message }.to_json
      end

      get '/cloudservers/request/:id' do |request_id|
        request    = CloudRequest.find(request_id)
        user       = User.find(request.requester)
        # TODO: get the login user based on the image and push that to the login instructions modal
        erb :cloudserver_request_details, locals: { request: request, user: user }
      end

      get '/cloudservers/request/partial/:id' do |request_id|
        erb :cloudserver_request_details_partial, locals: { request: CloudRequest.find(request_id) }
      end

      get '/cloudservers/request/progress/:id' do |request_id|
        # returns how much progress has been made so far on instances
        ff = CloudRequest.find(request_id).fulfilled?
        if request.xhr? # if this is a ajax request
          halt 200, {fulfilled: ff}.to_json
        else
          "#{ff}"
        end
      end

      # cloud instance types
      get '/cloudservers/flavors' do
        protected!

        erb :cloud_flavors, locals: { flavors: CloudFlavor.all }
      end

      post '/cloudservers/flavors' do
        id = params[:flavorid]
        name = params[:flavorname]
        vcpus = params[:vcpus]
        mem = params[:mem]
        disk = params[:disk]

        success    = true
        message    = 'Successfully added cloud flavor details'

        CloudFlavor.find_or_create_by(
            flavor_id: id,
            flavor_name: name,
            vcpus: vcpus,
            mem: mem,
            disk: disk
        )

        flash[:info] = message
        { success: success, msg: message }.to_json
      end

      delete '/cloudservers/flavors/:id' do |id|
        CloudFlavor.find_by(_id: id).delete
      end

      get '/cloudservers/images' do
        protected!

        erb :cloudimages, locals: { images: CloudImage.all }
      end

      post '/cloudservers/images' do
        imageid = params[:imageid]
        os = params[:os]
        osver = params[:osver]
        osarch = params[:osarch]
        osloginname = params[:osloginname]

        success    = true
        message    = "Successfully added cloud image details"

        CloudImage.find_or_create_by(
            image_id: imageid,
            os: os,
            os_ver: osver,
            os_arch: osarch,
            username: osloginname
        )

        flash[:info] = message
        { success: success, msg: message }.to_json
      end

      delete '/cloudservers/images/:id' do |id|
        CloudImage.find_by(_id: id).delete
      end

    end
  end
end