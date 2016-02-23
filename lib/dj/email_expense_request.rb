class EmailExpenseRequest < Struct.new(:settings, :admin, :request, :consultant)
  def perform
    email_body = <<EOBODY
      <p>This is a notification from Sync portal:</p>
      <p><strong>#{consultant.first_name} #{consultant.last_name}</strong> requested <strong>expense request</strong></p>
      <p>Request Details:</p>
      <table width="100%" border="0" cellspacing="0" cellpading="0">
        <tr>
          <td align="left" width="20%" valign="top"><strong>Expense Category:</strong></td>
          <td align="left" width="20%" valign="top">#{request.category}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Amount:</strong></td>
          <td align="left" width="20%" valign="top">#{request.amount.format}</td>
        <tr>
        <tr>
          <td align="left" width="20%" valign="top"><strong>Notes:</strong></td>
          <td align="left" width="20%" valign="top">#{request.notes}</td>
        <tr>
      </table>
      <br/>
      <p><strong>Things to do</strong>: Log in to sync portal (<a href="http://sync.cloudwick.com/certifications">sync.cloudwick.com</a>) to approve the request.</p>
      <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
    Pony.mail(
      from: 'Cloudwick Sync' + "<" + settings[:email] + ">",
      to: settings[:admin_group],
      subject: "Sync: Document Request Notification from #{consultant.first_name} #{consultant.last_name}",
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
    log 'successfully sent out expense request notification email'
  end

  def error
    log 'something went wrong sending expense request notification email out'
  end

  def failure
    log 'something went wrong sending expense request notification email out'
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
