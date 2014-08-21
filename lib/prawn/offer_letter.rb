require 'prawn'

class OfferLetter
  def initialize(name, company, signature, layout, start_date, end_date, dated, template, tmp_file)
    @name = name
    @company = company
    @signature = signature
    @layout = layout
    @address = if company =~ /Cloudwick|cloudwick/
                "39899 Balentine Dr\nSuite 380\nNewark, CA 94560\nPH: +1 (650) 346-5788\nFax: 954 827 5982"
               else
                "3220 Diable Ave\nHayward, CA, 94545\nPH: +1 (650) 346-5788\nFax: 954 827 5982"
               end
    @footer = if company =~ /Cloudwick|cloudwick/
                'Cloudwick Technologies Inc, 39899 Balentine Dr, Suite 380, Newark, CA 94560. PH: +1 (650) 346-5788'
               else
                'JB Micro Inc, 3220 Diable Ave, Hayward, CA, 94545. PH:  +1 (650) 346-5788'
               end
    @url = if company =~ /Cloudwick|cloudwick/
            '<u><link href="http://www.cloudwick.com">www.cloudwick.com</link></u>'
          else
            '<u><link href="http://www.jbmicro.com">www.jbmicro.com</link></u>'
          end
    @email = if company =~ /Cloudwick|cloudwick/
            '<u><link href="mailto:mani@cloudwikc.com">mani@coudwick.com</link></u>'
          else
            '<u><link href="mailto:mani@jbmicro.com">mani@jbmicro.com</link></u>'
          end
    @start_date = start_date
    @dated_date = dated
    @template = template
    @tmp_file = tmp_file
  end

  def build!
    Prawn::Document.generate(@tmp_file,
      page_layout: :portrait,
      margin: 75,
      info: {
        Title: 'Offer Letter',
        Author: 'Cloudwick Sync',
        Subject: "LT for #{@name}",
        Creator: @company,
        CreationDate: Time.now.strftime('%B %d, %Y')
      }) do |pdf|

      # background image
      pdf.image StringIO.new(@layout.read),
          :at  => [0, pdf.bounds.absolute_top],
          :fit => [pdf.bounds.absolute_right, pdf.bounds.absolute_top]

      # header
      pdf.bounding_box [pdf.bounds.left, pdf.bounds.top], :width  => pdf.bounds.width do
          pdf.font "Helvetica"
          pdf.text "Leave Letter for #{@name}", :align => :center, :size => 25
          pdf.stroke_horizontal_rule
      end

      pdf.move_down 50
      pdf.text "Dated #{@dated_date}", style: :bold, align: :right

      pdf.move_down 20
      pdf.text "To Whom It May Concern,", style: :bold

      pdf.move_down 20
      pdf.text "RE: Leave approval letter for Mr. #{@name}", style: :bold

      pdf.move_down 20
      pdf.text "Dear Sir/Madam,"

      pdf.move_down 20
      # body = <<-END.gsub(/\s+/, ' ')
      #   Mr. #{@name} has been granted leave from #{@start_date} to
      #   #{@end_date}. He will continue same job duties after coming back from
      #   vacation.
      # END
      body = @template
      pdf.text body, leading: 10, indent_paragraphs: 60

      pdf.move_down 20
      pdf.text "Sincerely,"

      pdf.image StringIO.new(@signature.read), width: 100, height: 50

      pdf.move_down 20
      pdf.font("Helvetica", size: 10) do
        pdf.text "Maninder Chhabra\nCEO\n#{@company}\n#{@address}\nEmail: #{@email}\nCorp Site: #{@url}", inline_format: true
      end

      # footer
      pdf.bounding_box [pdf.bounds.left, pdf.bounds.bottom + 25], :width  => pdf.bounds.width do
          pdf.font "Helvetica"
          pdf.stroke_horizontal_rule
          pdf.move_down(5)
          pdf.text @footer, :size => 8, align: :center, style: :bold, :color => "007700"
      end
    end
  end
end
