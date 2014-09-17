require 'net/smtp'

class EmailProjectNotification < Struct.new(:email_settings, :consultant)
  def perform
    consultant_name = "#{consultant.first_name.downcase}_#{consultant.last_name.downcase}"
    tmp_file = Tempfile.new(consultant_name)
    begin
      ProjectDocumentGenerator.new(
        consultant.id,
        tmp_file.path
      ).build!

      email_body = <<EOBODY
        <p>This is a nofication from Sync portal:</p>
        <p><strong>#{consultant.first_name}  #{consultant.last_name}</strong> has filled out the project form</p>
        <br/>
        <p>Attached is a pdf file that illustrates the user filled out form details.</p>
        <p>Thanks for using <strong>Cloudwick Sync.</strong></p>
EOBODY
      send_email_with_attachement(
        email_settings[:email],
        email_settings[:project_notification_group],
        email_settings[:admin_group],
        "Sync: Project add notification from #{consultant.first_name} #{consultant.last_name}",
        email_body,
        "#{consultant_name}_#{DateTime.now.strftime("%Y_%m_%d")}.pdf",
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
To: #{to.kind_of?(Array) && to.join(',') || to}
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
    log "sucessfully sent out project add notification email to #{email_settings[:project_notification_group]}"
  end

  def error
    log "something went wrong sending project add notification email out to #{email_settings[:project_notification_group]}"
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
