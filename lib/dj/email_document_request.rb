class EmailDocumentRequest < Struct.new(:settings, :admin, :request)
  def perform
    email_body = <<EOBODY
      <p>This is a nofication from Sync portal:</p>
      <p><strong>#{request.consultant_name}</strong> requested <strong>#{request.document_type}</strong></p>
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
      <p><strong>Things to do</strong>: Log in to sync portal (<a href="http://sync.cloudwick.com/documents">sync.cloudwick.com</a>) and approve the document request.</p>
      <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
    Pony.mail(
      from: 'Cloudwick Sync' + "<" + settings[:email] + ">",
      to: settings[:admin_group],
      subject: "Sync: Document Request Notification from #{request.consultant_name}",
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
    log "sucessfully sent out document request notification email to #{request.consultant_email}"
  end

  def error
    log "something went wrong sending document request notification email out to #{request.consultant_email}"
  end

  def failure
    log "something went wrong sending document request notification email out"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
