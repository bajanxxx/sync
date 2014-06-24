require_relative 'dj/campaign_mail'

class VendorCampaign
  def initialize(template_name, all_vendors, replied_vendors)
    @template_name = template_name
    @all_vendors = all_vendors
    @replied_vendors = replied_vendors
    @vendors = []
  end

  def start
    @vendors = if @all_vendors == 'true'
                 Vendor.where(unsubscribed: false, bounced: false).all.entries
               else
                 Vendor.where(
                   :email_replies_recieved.gt => 0,
                   unsubscribed: false,
                   bounced: false
                 ).all.entries
               end
    @vendors.each do |vendor|
      Delayed::Job.enqueue(
        CampaignEmail.new(vendor, @template_name, 'vendor'),
        queue: 'vendor_emails',
        priority: 5,
        run_at: 5.seconds.from_now
      )
    end
    return "Queued #{@vendors.count} emails..."
  end
end
