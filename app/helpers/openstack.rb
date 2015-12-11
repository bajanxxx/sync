module Sync
  module Helpers
    module Openstack
      def create_openstack_connection
        Fog::Compute.new({
                             provider:            'openstack',
                             openstack_api_key:   @settings[:openstack_api_key],
                             openstack_username:  @settings[:openstack_username],
                             openstack_auth_url:  @settings[:openstack_auth_url],
                             openstack_tenant:    @settings[:openstack_tenant],
                             connection_options:  { connect_timeout: 5 }
                         })
      rescue Excon::Errors::Unauthorized
        return nil
      rescue Excon::Errors::BadRequest
        return nil
      rescue Excon::Errors::Timeout
        return nil
      end
    end
  end
end