require_relative 'dj/campaign_mail'

class CustomerCampaign
  def initialize(template_name, customer_vertical, replied_customers, nodups)
    @template_name = template_name
    @customer_vertical = customer_vertical
    @replied_customers_only = replied_customers || false
    @nodups = nodups || false
    @customers = []
  end

  def start
    @customers = if @customer_vertical.downcase == 'all'
                   if @replied_customers_only == 'true'
                     Customer.where(
                       :email_replies_recieved.gt => 0,
                       unsubscribed: false,
                       bounced: false
                     ).all.entries
                   elsif @nodups == 'true'
                     Customer.where(
                       :emails_sent.lt => 1,
                       unsubscribed: false,
                       bounced: false
                     ).all.entries
                   else
                     Customer.where(
                       unsubscribed: false,
                       bounced: false
                     ).all.entries
                   end
                 else
                   if @replied_customers_only == 'true'
                     Customer.where(
                       industry: @customer_vertical,
                       :email_replies_recieved.gt => 0,
                       unsubscribed: false,
                       bounced: false
                     ).all.entries
                   elsif @nodups == 'true'
                     Customer.where(
                       industry: @customer_vertical,
                       :emails_sent.lt => 1,
                       unsubscribed: false,
                       bounced: false
                     ).all.entries
                   else
                     Customer.where(
                       industry: @customer_vertical,
                       unsubscribed: false,
                       bounced: false
                     ).all.entries
                   end
                 end
    @customers.each do |customer|
      Delayed::Job.enqueue(
        CampaignEmail.new(customer, @template_name, 'customer'),
        queue: 'customer_emails',
        priority: 10,
        run_at: 5.seconds.from_now
      )
    end
    return "Queued #{@customers.count} emails..."
  end
end
