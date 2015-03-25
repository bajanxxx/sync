class CloudInstance
  include Mongoid::Document

  field :user_id, type: String
  field :instance_id, type: String
  field :instance_name, type: String
  field :flavor_id,  type: String

  field :image_id, type: String
  field :os_flavor, type: String
  field :ip_address, type: String
  field :vcpus, type: Integer
  field :mem, type: Integer
  field :disk, type: Integer
  # Status could be:
  # NOTAPPROVED (admin has not yet granted the request)
  # ACTIVE
  # BUILDING (server has not finished building)
  # DELETED (The server is permanetly)
  # ERROR
  # HARD_REBOOT (The server is hard rebooting. This is equivalent to pulling the power plug on a physical server, plugging it back in, and rebooting it.)
  # PASSWORD (The password is being reset on the server)
  # PAUSED (The server is paused and continues to run in frozen state. The state of the server is stored in RAM.)
  # REBOOT (The server is in a soft reboot state. A reboot command was passed to the operating system.)
  # REBUILD (The server is currently being rebuilt from an image.)
  # RESCUED (The server is in rescue mode. A rescue image is running with the original server image attached.)
  # RESIZED (The server is down while it performs a differential copy of data that changed during its initial copy.)
  # SHUTOFF. The virtual machine (VM) was powered down by the user, but not through the OpenStack Compute API. For example, the user issued a shutdown -h command from within the server instance. If the OpenStack Compute manager detects that the VM was powered down, it transitions the server instance to the SHUTOFF status. If you use the OpenStack Compute API to restart the instance, the instance might be deleted first, depending on the value in the shutdown_terminate database field on the Instance model.
  # SOFT_DELETED. The server is marked as deleted but the disk images are still available to restore.
  # STOPPED. The server is powered off and the disk image still persists.
  # SUSPENDED. The server is suspended either by request or necessity. This status appears for only XenServer/XCP, KVM, and ESXi hypervisors. Administrative users can suspend an instance if it is infrequently used or to perform system maintenance. When you suspend an instance, its VM state is stored on disk, all memory is written to disk, and the virtual machine is stopped. Suspending an instance is similar to placing a device in hibernation; memory and vCPUs become available to create other instances.
  # UNKNOWN. The state of the server is unknown. Contact your cloud provider.
  # VERIFY_RESIZE. The system awaits confirmation that the server is operational after a move or resize.
  # REVERT_RESIZE. Because a server resize or migration failed, the destination server is being cleaned up as the original source server restarts.
  # TIMEDOUT. waiting for the server to come live
  # TERMINATED
  field :state, type: String, default: 'NOTAPPROVED'
  field :uptime, type: String
  field :terminated, type: Boolean, default: false
  # lock is used by various programs trying to update the state of the instance
  field :lock?, type: Boolean, default: false
  field :hosted_on, type: String

  field :volumes_count, type: Integer, default: 0

  belongs_to :cloud_request
end
