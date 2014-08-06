# Sends out email using pony api
class EmailJobPosting < Struct.new(:admin, :job, :user, :notes)
  Settings.load!(File.expand_path("../../../config/config.yml", __FILE__))
  def perform
    email_body = <<EOBODY
      <p>Hi,</p>
      <p><strong>#{admin}</strong> sent the following link: <a href="#{job.url}">#{job.title}</a> for the job posting. Please take a look at this posting.</p>
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
      <p><strong>Notes</strong>: #{notes}</p>
      <p><strong>Important</strong>: <font color="red"> Update your resume as per the job requirement. Try to include all the technologies.</font></p>
      <p>Thanks,<br/>Shiva.</p>
EOBODY
    Pony.mail(
      from: Settings.email.split('@').first + "<" + Settings.email + ">",
      to: user.email,
      cc: Settings.cc,
      subject: "Apply/Check this job: #{job.title}(#{job.location})",
      headers: { 'Content-Type' => 'text/html' },
      body: email_body,
      via: :smtp,
      via_options: {
        address: Settings.smtp_address,
        port: Settings.smtp_port,
        enable_starttls_auto: true,
        user_name: Settings.email,
        password: Settings.password,
        authentication: :plain,
        domain: 'localhost.localdoamin'
      }
    )
  end

  def success
    log "sucessfully sent out email to #{user.email}"
    user.applications.find_or_create_by(job_url: job.url) do |application|
      application.add_to_set(:comments, 'Forwarded to consultant')
      application.add_to_set(:status, 'AWAITING_UPDATE_FROM_USER')
    end
    job.add_to_set(:trigger, 'SEND_CONSULTANT')
    job.update_attribute(:read, true)
  end

  def error
    log "something went wrong sending email out to #{user.email}"
  end

  def failure
    log "something went wrong sending email out"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end