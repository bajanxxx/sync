class EmailRequestStatus < Struct.new(:settings, :admin, :request)
  def perform
    email_body = <<EOBODY
      <p>Hi,</p>
      <p>This update is to let you know that <strong>#{admin}</strong> has <strong>#{request.status}</strong> your request for documents.</p>
      <p>Request Details:</p>
      <table width="100%" border="0" cellspacing="0" cellpading="0">
        <tr>
          <td align="left" width="20%" valign="top"><strong>Request Made on</strong></td>
          <td align="left" width="20%" valign="top">#{request.create_at}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Request Type:</strong></td>
          <td align="left" width="20%" valign="top">#{request.document_type}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Company:</strong></td>
          <td align="left" width="20%" valign="top">#{request.company}</td>
        <tr>
      </table>
      <br/>
      <p><strong>Important</strong>: <font color="red"> Contact #{admin} for more information.</font></p>
      <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
    Pony.mail(
      from: settings[:email].split('@').first + "<" + settings[:email] + ">",
      to: request.consultant_email,
      cc: settings[:cc],
      subject: "Status of the document request (#{request.document_type}) you made",
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
    log "sucessfully sent out status update email to #{request.consultant_email}"
  end

  def error
    log "something went wrong sending status update email out to #{request.consultant_email}"
  end

  def failure
    log "something went wrong sending status update email out"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end