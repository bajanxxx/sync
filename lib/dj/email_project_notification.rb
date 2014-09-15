class EmailProjectNotification < Struct.new(:settings, :consultant)
  def perform
    email_body = <<EOBODY
      <p>This is a nofication from Sync portal:</p>
      <p><strong>#{consultant.first_name + consultant.last_name}</strong> has filled out the project form</p>
      <br/>
      <p><strong>Things you could do</strong>: Log in to sync portal (<a href="http://sync.cloudwick.com">sync.cloudwick.com</a>) to follow up with the project information.</p>
      <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
    Pony.mail(
      from: 'Cloudwick Sync' + "<" + settings[:email] + ">",
      to: settings[:project_notification_group],
      subject: "Sync: Project add notification from #{consultant.first_name + consultant.last_name}",
      headers: { 'Content-Type' => 'text/html' },
      body: email_body,
      via: :smtp,
      via_options: {
        address: settings[:smtp_address],
        port: settings[:smtp_port],
        enable_starttls_auto: true,
        user_name: settings[:email],
        password: settings[:password],
        authentication: :plain,
        domain: 'localhost.localdoamin'
      }
    )
  end

  def success
    log "sucessfully sent out project add notification email to #{settings[:admin_group]}"
  end

  def error
    log "something went wrong sending project add notification email out to #{settings[:admin_group]}"
  end

  def failure
    log "something went wrong sending project add notification email out"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
