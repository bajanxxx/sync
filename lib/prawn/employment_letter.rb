require 'prawn'
require 'mini_magick'

class EmploymentLetter
  def initialize(name, company, signature, layout, start_date, dated, template, tmp_file)
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
    @everify = if company =~/Cloudwick|cloudwick/
                642485
              else
                270262
              end
    @start_date = start_date
    @dated_date = dated
    @template = template
    @tmp_file = tmp_file
  end

  def get_scale
    image_file = MiniMagick::Image.read(StringIO.new(@layout))
    pdf_width = PDF::Core::PageGeometry::SIZES["A4"][0]
    pdf_height = PDF::Core::PageGeometry::SIZES["A4"][1]
    [ pdf_width.fdiv(image_file[:width]), pdf_height.fdiv(image_file[:height]) ].max
  end

  def build!
    Prawn::Document.generate(@tmp_file,
      page_layout: :portrait,
      margin: 75,
      page_size: 'A4',
      background: StringIO.new(@layout),
      background_scale: get_scale,
      info: {
        Title: 'Employment Letter',
        Author: 'Cloudwick Sync',
        Subject: "LT for #{@name}",
        Creator: @company,
        CreationDate: Time.now.strftime('%B %d, %Y')
      }
    ) do |pdf|

    #   pdf.repeat :all do
    #    # header
    #    pdf.bounding_box [pdf.bounds.left, pdf.bounds.top], :width  => pdf.bounds.width do
    #      pdf.font "Helvetica"
    #      pdf.text "Employment Letter for #{@name}", :align => :center, :size => 25
    #      pdf.stroke_horizontal_rule
    #    end
     #
    #    # footer
    #    pdf.bounding_box [pdf.bounds.left, pdf.bounds.bottom + 25], :width  => pdf.bounds.width do
    #      pdf.font "Helvetica"
    #      pdf.stroke_horizontal_rule
    #      pdf.move_down(5)
    #      pdf.text @footer, :size => 8, align: :center, style: :bold, :color => "007700"
    #    end
    #  end # end repeat

      # body
      pdf.bounding_box([pdf.bounds.left, pdf.bounds.top - 75], :width  => pdf.bounds.width, :height => pdf.bounds.height - 125) do
        pdf.text "Dated #{@dated_date}", style: :bold, align: :right

        pdf.move_down 20
        pdf.text "To Whom It May Concern,", style: :bold

        pdf.move_down 20
        pdf.text "RE: Employment verification letter for #{@name}", style: :bold

        pdf.move_down 20
        pdf.text "Dear Sir/Madam,"

        pdf.move_down 20
        body = @template
        pdf.text body, inline_format: true

        pdf.move_down 20

        pdf.table([
            [pdf.make_cell(content: 'Sincerely,', inline_format: true)],
            [{image: StringIO.new(@signature), image_height: 50, image_width: 100}],
            [pdf.make_cell(content: "Maninder Chhabra\nCEO\n#{@company}\n#{@address}\nEmail: #{@email}\nCorp Site: #{@url}", inline_format: true)]
          ],
          cell_style: {inline_format: true, borders: []},
          width: pdf.bounds.width,
        )

      end # end body
    end # end prawn block
  end # end build!
end
