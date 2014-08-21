# Generates documents such as leaveletter, offerletter, employmentletter and
# emails them out to specified email address
class GenerateDocument < Struct.new(:email, :email_settings, :type, :admin, :signature, :layout, :options)
  def perform
    tmp_file = Tempfile.new(options[:cname].downcase.gsub(' ', '_'))
    begin
      case type
      when 'LEAVELETTER'
        LeaveLetter.new(
          options[:cname],
          options[:company],
          signature,
          layout,
          Date.strptime(options[:start_date], "%m/%d/%Y").strftime('%B %d, %Y'),
          Date.strptime(options[:end_date], "%m/%d/%Y").strftime('%B %d, %Y'),
          Date.strptime(options[:dated], "%m/%d/%Y").strftime('%B %d, %Y'),
          options[:template],
          tmp_file.path
        ).build!
        log "Generated pdf to #{tmp_file.path}"
      when 'OFFERLETTER'
        OfferLetter.new(
          options[:cname],
          options[:company],
          signature,
          layout,
          Date.strptime(options[:start_date], "%m/%d/%Y").strftime('%B %d, %Y'),
          Date.strptime(options[:dated], "%m/%d/%Y").strftime('%B %d, %Y'),
          options[:template],
          tmp_file.path
        ).build!
        log "Generated pdf to #{tmp_file.path}"
      when 'EMPLOYMENTLETTER'
        EmploymentLetter.new(
          options[:cname],
          options[:company],
          signature,
          layout,
          Date.strptime(options[:start_date], "%m/%d/%Y").strftime('%B %d, %Y'),
          Date.strptime(options[:dated], "%m/%d/%Y").strftime('%B %d, %Y'),
          options[:template],
          tmp_file.path
        ).build!
        log "Generated pdf to #{tmp_file.path}"
      else
        log "Cannot find specified action for document type #{type}"
      end
      email_body = <<EOBODY
        <p>Hi,</p>
        <p><strong>#{admin}</strong> sent the following document that you requested.
        Please take a look at the attached file and reply back if something needs to be changed.</p>
        <p>Thanks,<br/>#{admin}.</p>
EOBODY
      Pony.mail(
        from: email_settings[:email].split('@').first + "<" + email_settings[:email] + ">",
        to: email,
        # TODO uncomment cc
        # cc: email_settings[:cc],
        subject: "The document (#{type}) you requested",
        # headers: { 'Content-Type' => 'text/html' },
        headers: { "Content-Type" => "multipart/mixed" },
        html_body: email_body,
        via: :smtp,
        via_options: {
          address: email_settings[:smtp_address],
          port: email_settings[:smtp_port],
          enable_starttls_auto: true,
          user_name: email_settings[:email],
          password: email_settings[:password],
          authentication: :plain,
          domain: 'localhost.localdoamin',
        },
        attachments: {"#{options[:cname].downcase.gsub(' ', '_')}_#{type.downcase}.pdf" => File.read(tmp_file.path)}
      )
    ensure
      tmp_file.close
    end
  end

  def success
    log "sucessfully sent out email to #{email} with attachement (#{type})"
  end

  def error
    log "something went wrong sending email out to #{email}"
  end

  def failure
    log "something went wrong sending email out (tried 5 attempts)"
  end

  # overrides the Delayed::Worker.max_attempts only for this job
  def max_attempts
    5
  end

  def log(text)
    Delayed::Worker.logger.info("#{Time.now.strftime('%FT%T%z')}: [#{self.class.name} (pid: #{Process.pid})] #{text}")
  end
end
