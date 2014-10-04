require 'fog'
require 'securerandom'
require 'fileutils'

module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def OS.mac?
   (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def OS.unix?
    !OS.windows?
  end

  def OS.linux?
    OS.unix? and not OS.mac?
  end
end

class CloudInstances
  def initialize(os_auth_url, os_username, os_password, os_tenant)
    @os_auth_url = os_auth_url
    @os_username = os_username
    @os_password = os_password
    @os_tenant = os_tenant
  end

  def create_connection
    Fog::Compute.new({
                       provider:           'openstack',
                       openstack_api_key:  @os_password,
                       openstack_username: @os_username,
                       openstack_auth_url: @os_auth_url,
                       openstack_tenant:   @os_tenant,
                       connection_options: { connect_timeout: 5 }
                     })
  rescue Excon::Errors::Unauthorized => ex
    # puts 'Invalid OpenStack Credentials' + ex.message
    # puts ex.backtrace.join("\n")
    return nil
  rescue Excon::Errors::BadRequest => ex
    # puts 'Malformed connection options' + ex.message
    # if ex.response.body
    #   puts JSON.parse(ex.response.body)['badRequest']['message']
    # end
    # puts ex.backtrace.join("\n")
    return nil
  rescue Excon::Errors::Timeout
    # puts 'Connection Timedout, cannot connect to openstack'
    return nil
  end

  def valid_connection?(conn)
    conn.servers.length
    true
  rescue Excon::Errors::Forbidden, Excon::Errors::Unauthorized
    false
  end

  def create_sg!(conn, group)
    unless conn.security_groups.map {|x| x.name }.include?(group)
      # puts "Creating a new security group with name: #{group}"
      conn.security_groups.create(name: group, description: 'group managed by ankus')
    end

    sec_group_id = conn.security_groups.find {|g| g.name == group}.id
    sec_group = conn.security_groups.get(sec_group_id)
    # check and authorize for ssh port
    open_ssh = sec_group.security_group_rules.detect do |ip_permission|
      ip_permission.ip_range.first && ip_permission.ip_range['cidr'] == '0.0.0.0/0' &&
          ip_permission.from_port == 22 &&
          ip_permission.to_port == 22 &&
          ip_permission.ip_protocol == 'tcp'
    end
    open_all_tcp = sec_group.security_group_rules.detect do |ip_permission|
      ip_permission.ip_range.first && ip_permission.ip_range['cidr'] == '0.0.0.0/0' &&
          ip_permission.from_port == 1 &&
          ip_permission.to_port == 65535 &&
          ip_permission.ip_protocol == 'tcp'
    end
    open_all_udp = sec_group.security_group_rules.detect do |ip_permission|
      ip_permission.ip_range.first && ip_permission.ip_range['cidr'] == '0.0.0.0/0' &&
          ip_permission.from_port == 1 &&
          ip_permission.to_port == 65535 &&
          ip_permission.ip_protocol == 'udp'
    end
    open_all_icmp = sec_group.security_group_rules.detect do |ip_permission|
      ip_permission.ip_range.first && ip_permission.ip_range['cidr'] == '0.0.0.0/0' &&
          ip_permission.from_port == -1 &&
          ip_permission.to_port == -1 &&
          ip_permission.ip_protocol == 'icmp'
    end
    open_icmp_echo_req = sec_group.security_group_rules.detect do |ip_permission|
      ip_permission.ip_range.first && ip_permission.ip_range['cidr'] == '0.0.0.0/0' &&
          ip_permission.from_port == 0 &&
          ip_permission.to_port == -1 &&
          ip_permission.ip_protocol == 'icmp'
    end
    open_icmp_echo_rep = sec_group.security_group_rules.detect do |ip_permission|
      ip_permission.ip_range.first && ip_permission.ip_range['cidr'] == '0.0.0.0/0' &&
          ip_permission.from_port == 8 &&
          ip_permission.to_port == -1 &&
          ip_permission.ip_protocol == 'icmp'
    end
    unless open_ssh
      # puts "Opening SSH port in security group: #{group}"
      conn.create_security_group_rule(sec_group_id, 'tcp', 22, 22, '0.0.0.0/0')
    end
    # TODO: authorize specific ports for hadoop, hbase
    unless open_all_tcp
      # puts "Opening all TCP port(s) in security group: #{group}"
      conn.create_security_group_rule(sec_group_id, 'tcp', 1, 65535, '0.0.0.0/0')
    end
    unless open_all_udp
      # puts "Opening all UDP port(s) in security group: #{group}"
      conn.create_security_group_rule(sec_group_id, 'udp', 1, 65535, '0.0.0.0/0')
    end
    unless open_all_icmp
      unless open_icmp_echo_req
        # puts "Opening all ICMP Req port(s) in security group: #{group}"
        conn.create_security_group_rule(sec_group_id, 'icmp', 0, -1, '0.0.0.0/0')
      end
      unless open_icmp_echo_rep
        # puts "Opening all ICMP Rep port(s) in security group: #{group}"
        conn.create_security_group_rule(sec_group_id, 'icmp', 8, -1, '0.0.0.0/0')
      end
    end
  end

  def create_user!(user_email, user_obj)
    user_name = user_email.split('@').first.gsub('.', '_')

    if OS.linux?
      `grep -E '^#{user_name}' /etc/passwd`
      unless $?.exitstatus # user does not eixst in the gateway box
        # puts "Creating a new linux user with username: #{user_name}"
        password = SecureRandom.base64(10)
        salt = "$5$a1"
        passowrd_hash = password.crypt(salt)

        result = system("useradd -m -p '#{password_hash}' #{user_name}")
        if result
          # create user in mongo
          user_obj.update_attributes(
            lun: user_name,
            lpwd: password
          )
        end
      end # end unless
    end
  end

  def create_kp!(conn, user_email, user_obj)
    # Check if the user already has key pair in the document
    user_name = user_email.split('@').first.gsub('.', '_')

    # create a linux user
    create_user!(user_email, user_obj)

    if OS.linux?
      ssh_home  = "/home/#{user_name}/.ssh"
      ssh_pem   = "#{ssh_home}/id_rsa"
      ssh_pub   = "#{ssh_home}/id_rsa.pub"
    elsif OS.mac?
      ssh_home = "/tmp/#{user_name}"
      ssh_pem  = "#{ssh_home}/#{user_name}.pem"
      ssh_pub  = "#{ssh_home}/#{user_name}.pub"
    end

    if conn.key_pairs.get(user_name) # key pair exists in openstack
      # puts "key_pair #{user_name} already exists in openstack"
      unless File.exist?(ssh_pem) # file does alredy exists in local, lets get it from mongo
        # puts "But, key_pair does not exist on the gateway box, attempting to install the key..."
        # Attempt to create the ssh home path if does not exist already on the box
        unless File.exist?(ssh_home)
          FileUtils.mkdir_p(ssh_home)
          FileUtils.chmod(0700, ssh_home)
        end
        File.open(ssh_pem, 'w') { |file| file.write(user_obj.pem) }
      else
        # puts "key_pair #{user_name} file exists on the gateway box"
      end
    else # key pair does not exist in openstack lets create one kp and update in mongo
      # puts "Creating a new key pair with name: #{user_name}"
      kp = conn.key_pairs.create(name: user_name)

      FileUtils.mkdir_p(ssh_home)
      FileUtils.chmod(0700, ssh_home)
      FileUtils.chown(user_name, user_name, ssh_home) if OS.linux? # : FileUtils.chown(user_name, 'wheel', ssh_home)
      File.open(ssh_pem, 'w') { |file| file.write(kp.private_key) }
      FileUtils.chmod(0600, ssh_pem)
      # OS.linux? ? FileUtils.chown(user_name, user_name, ssh_pem) : FileUtils.chown(user_name, 'wheel', ssh_pem)
      # File.open(ssh_pub, 'w') { |file| file.write(kp.ssh_public_key) }
      # FileUtils.chmod(0644, ssh_pub)
      # OS.linux? ? FileUtils.chown(user_name, user_name, ssh_pub) : FileUtils.chown(user_name, 'wheel', ssh_pub)

      user_obj.update_attributes(pem: kp.private_key, pub: kp.public_key, fin: kp.fingerprint)
    end
  end

  def create_server!(conn, name, flavor_id, ssh_key, image_id, sec_groups)
    # puts "Creating instance with name: #{name}, flavor: #{flavor_id}, image_id: #{image_id}"
    server = conn.servers.create(
      name: name,
      flavor_ref: flavor_id,
      image_ref: image_id,
      # :personality => [
      #   {
      #     :path => '/tmp/authorized_keys',
      #     :contents => Base64.encode64(File.read(File.expand_path(ssh_key_path)))
      #   }
      # ],
      :key_name => ssh_key,
      :security_groups => sec_groups
    )
    # return the server instance to be consumed by downstream
    server
  end

  def update_server!(server, cloud_instance_obj)
    # reload the server instance
    # puts "Reloading server object, acquiring lock on the server object ..."
    cloud_instance_obj.update_attributes!(lock?: true)
    server.reload
    # wait for the server to get created
    # puts "Waiting for the server #{server_name} to get ready ..."
    begin
      server.wait_for(100, 5) { ready? }
    rescue Fog::Errors::TimeoutError
      cloud_instance_obj.update_attributes!(state: 'TIMEDOUT', lock?: false)
    else
      # Update the instances details in db
      cloud_instance_obj.update_attributes!(
        instance_id: server.id,
        ip_address: server.addresses['novanetwork'].first['addr'],
        hosted_on: server.os_ext_srv_attr_host,
        state: server.state,
        lock?: false
      )
    end
  end
end