require_relative '../cloud_instances'

class DeleteCloudInstances < Struct.new(:settings, :request, :user)
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

        request.cloud_instances.each do |instance|
          log "Deleting server #{instance.instance_id}"
          ci.delete_server!(
            conn,
            instance.instance_id,
            false
          )
          instance.update_attributes!(terminated: true)
        end
        log "Compelted request to delete servers: #{request}"
      rescue Exception => ex
        # something went wrong processing the request remove lock and exit
        log "Something went wrong processing the request: #{request}"
        log "Exception: #{ex.message}"
        log "Backtrace: " + ex.backtrace.join("\n")
        request.update_attributes!(lock?: false)
      else
        # now we can safely update the request as fulfilled and release the lock
        request.update_attributes!(fulfilled?: true, lock?: false, active?: false)
      end
    end
  end

  def success
    log "sucessfully completed request for #{request.requester} to delete #{request.cloud_instances.count} instances"
  end

  def error
    log "something went wrong processing request for #{request.requester} to delete #{request.cloud_instances.count} instances"
  end

  def failure
    log "something went wrong processing request for #{request.requester} to delete #{request.cloud_instances.count} instances. Giving up!"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    1
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
