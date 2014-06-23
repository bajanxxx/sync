class CampaignEmail < Struct.new(:user, :template_name, :type)

  def get_template
    Template.find_by(name: template_name)
  end

  # Send email out using mailgun
  def send_mail
    Settings.load!(File.expand_path("../../../config/config.yml", __FILE__))
    to_mail = type == 'customer' ? Settings.mailgun_customer_email : Settings.mailgun_vendor_email
    full_name = to_mail.split('@').first.split('.')
    firstname = full_name.first.capitalize
    lastname  = if full_name.length > 1
                  full_name.last.capitalize
                else
                  nil
                end
    display_name = if lastname
                     firstname + ' ' + lastname
                   else
                     firstname
                   end
    template = get_template
    campaign_id = template.name.downcase.gsub(' ', '_')
    body = template.content
    subject = template.subject
    message = if body
                 body.sub(/USERNAME/, user.first_name)
              else
                raise "Got nil email body"
              end
    RestClient.post(
      "https://api:#{Settings.mailgun_api_key}@api.mailgun.net/v2/#{Settings.mailgun_domain}/messages",
      from: display_name + "<" + to_mail + ">",
      to: user.email,
      subject: subject,
      html: message,
      'o:campaign' => campaign_id,
      'o:tag' => 'Cloudwick Email Campaigning',
      'h:Message-Id' => "#{campaign_id}@#{Settings.mailgun_domain}"
    )
  end

  def perform
    if user.sent_templates.include?(get_template.id)
      # email for same template has already been sent out
      # silently ignore it
    else
      send_mail
    end
  end

  def success
    if user.sent_templates.include?(get_template.id)
      log "Ok, skipping this email (#{user.email}) as we sent the same template before"
    else
      log "sucessfully sent out email to #{user.email}"
      user.inc(:emails_sent, 1)
      user.add_to_set(:sent_templates, get_template.id)
    end
  end

  def error
    log "something went wrong sending email out to #{user.email}"
    user.update_attribute(:skipped, true)
    user.add_to_set(:skipped_templates, get_template.id)
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
