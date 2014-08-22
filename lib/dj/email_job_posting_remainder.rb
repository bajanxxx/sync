class EmailJobPostingRemainder < Struct.new(:settings, :admin, :job, :email)
  def perform
    email_body = <<EOBODY
      <p>Hi,</p>
      <p>This is a reminder from <strong>#{admin}</strong> regarding job posting: <a href="#{job.url}">#{job.title}</a> you have been tracking in cloudwick's job portal.</p>
      <p>Follow up with the vendor and let me know the status.</p>
      <p>Job Details:</p>
      <table width="100%" border="0" cellspacing="0" cellpading="0">
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Title</strong></td>
          <td align="left" width="20%" valign="top">#{job.title}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Location</strong></td>
          <td align="left" width="20%" valign="top">#{job.location}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Posted</strong></td>
          <td align="left" width="20%" valign="top">#{job.date_posted}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Job Skills</strong></td>
          <td align="left" width="20%" valign="top">#{job.skills}</td>
        <tr>
      </table>
      <br/>
      <p><strong>Important</strong>: <font color="red"> Update the status of the posting in the <strong>job_portal</strong>.</font></p>
      <p>Thanks,<br/>#{admin}.</p>
EOBODY
    Pony.mail(
      from: 'Cloudwick Sync' + "<" + settings[:email] + ">",
      to: email,
      cc: settings[:cc],
      subject: "Remainder for job posting: #{job.title}(#{job.location})",
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
    log "sucessfully sent out remainder email to #{email}"
  end

  def error
    log "something went wrong sending remainder email out to #{email}"
  end

  def failure
    log "something went wrong sending remainder email out"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
