require 'net/smtp'

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
        <p><strong>#{admin}</strong> sent the following document that you have requested.
        Please take a look at the attached file and reply back if something needs to be changed.</p>
        <p><em><strong>Note</strong>: This email is generated by cloudwick sync portal. If you have received this email by error please contact <a href="mailto:admin@cloudwick.com?Subject=Sync%20Misplaced%20Email">admin</a>.</em></p>
        <p>Thanks,<br/>#{admin}.</p>
EOBODY
      send_email_with_attachement(
        email_settings[:email],
        email,
        email_settings[:admin_group],
        "Sync: The document (#{type}) you requested",
        email_body,
        "#{options[:cname].downcase.gsub(' ', '_')}_#{type.downcase}.pdf",
        tmp_file.path
      )
    ensure
      tmp_file.close
    end
  end

  def send_email(from, to, mailtext)
    begin
      smtp = Net::SMTP.new email_settings[:smtp_address], email_settings[:smtp_port]
      smtp.enable_starttls
      smtp.start('cloudwick.com', email_settings[:email], email_settings[:password], :login) do
        smtp.send_message(mailtext, from, to)
      end
    rescue => e
      raise "Exception occured: #{e} "
      exit -1
    end
  end

  def send_email_with_attachement(from, to, cc, subject, body, attachment_name, attachment)
    begin
      filecontent = File.read(attachment)
      encodedcontent = [filecontent].pack("m") # base64
    rescue
      raise "Could not read file #{attachment}"
    end

    marker = (0...50).map{ ('a'..'z').to_a[rand(26)] }.join

    part1 =<<EOF
From: Cloudwick Sync <#{from}>
To: #{to}
Cc: #{cc}
Subject: #{subject}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=#{marker}
--#{marker}
EOF

    # Define the message action
    part2 =<<EOF
Content-Type: text/html
Content-Transfer-Encoding:8bit

#{body}
--#{marker}
EOF

    # Define the attachment section
    part3 =<<EOF
Content-Type: application/pdf; name=\"#{attachment_name}\"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="#{attachment_name}"

#{encodedcontent}
--#{marker}--
EOF

    mailtext = part1 + part2 + part3

    send_email(from, to, mailtext)
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
