require_relative '../cloud_instances'

class CreateCloudInstances < Struct.new(:settings, :request, :user)
  def perform
    ci = CloudInstances.new(
      settings[:openstack_auth_url],
      settings[:openstack_username],
      settings[:openstack_api_key],
      settings[:openstack_tenant]
    )

    conn = ci.create_connection
    unless conn
      log "Cannot connect to openstack cluster, failing silently."
      request.update_attributes!(connection_failed?: true)
    else
      begin
        log "Acquiring lock on request: #{request}"
        # now lets lock the request so that no other process can work on it
        request.update_attributes!(lock?: true)

        user_email = request.requester
        user_name  = user_email.split('@').first.gsub('.', '_')

        # try create linux user, a key pair to login to the instances and a security group
        ci.create_kp!(conn, user_email, user)

        # try creating a security group and update rules
        ci.create_sg!(conn, 'ankus')

        server_objs = {}

        request.cloud_instances.each do |instance|
          server_objs[instance.instance_name] = ci.create_server!(
            conn,
            instance.instance_name,
            instance.flavor_id,
            user_name,
            instance.image_id,
            ['ankus']
          )
        end

        server_objs.each do |sn, so|
          log "Waiting for server #{sn} to get created ... Timeout's in 100 seconds"
          ci.update_server!(so, CloudInstance.find_by(instance_name: sn))
        end
      rescue
        # something went wrong processing the request remove lock and exit
        log "Something went wrong processing the request: #{request}, resetting flags (fulfilled -> false, lock? -> false)"
        request.update_attributes!(fulfilled?: false, lock?: false)
      else
        # now we can safely update the request as fulfilled and release the lock
        log "compelted request: #{request}"
        request.update_attributes!(fulfilled?: true, lock?: false, connection_failed?: false)
      end
    end
  end

  def success
    log "sucessfully completed request for #{request.requester} to create #{request.cloud_instances.count} instances"
  end

  def error
    log "something went wrong processing request for #{request.requester} to create #{request.cloud_instances.count} instances"
  end

  def failure
    log "something went wrong processing request for #{request.requester} to create #{request.cloud_instances.count} instances. Giving up!"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    1
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
