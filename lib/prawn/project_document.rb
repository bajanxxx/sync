require 'prawn'
require 'mini_magick'

class ProjectDocumentGenerator
  def initialize(consultant_id, tmp_file)
    @consultant_id = consultant_id
    @consultant = Consultant.find_by(email: consultant_id)
    @details = Detail.find_by(consultant_id: consultant_id)
    @cloudwick_color = '1278bf'
    @tmp_file = tmp_file
    @background_image = File.expand_path(File.join(File.dirname(__FILE__), "images/cloudwick_project_template.png"))
  end

  def get_scale
    image_file = MiniMagick::Image.open(@background_image)
    pdf_width = PDF::Core::PageGeometry::SIZES["A4"][0]
    pdf_height = PDF::Core::PageGeometry::SIZES["A4"][1]
    [ pdf_width.fdiv(image_file[:width]), pdf_height.fdiv(image_file[:height]) ].max
  end

  def build!
    Prawn::Document.generate(@tmp_file,
      page_layout: :portrait,
      margin: 25,
      page_size: 'A4',
      background: @background_image,
      background_scale: get_scale,
      info: {
        Title: 'Consultant Project Information',
        Author: 'Cloudwick Sync',
        Subject: "Project information from #{@consultant_id}",
        Creator: 'Cloudwick Inc',
        CreationDate: Time.now.strftime('%B %d, %Y')
      }
    ) do |pdf|

      pdf.repeat :all do
        # header
        pdf.bounding_box [pdf.bounds.left, pdf.bounds.top - 50], :width  => pdf.bounds.width do
          pdf.font "Helvetica"
          pdf.text "Project Information from <color rgb='#{@cloudwick_color}'>#{@consultant.first_name} #{@consultant.last_name}</color>", :align => :center, :size => 15, inline_format: true
          pdf.stroke_horizontal_rule
        end
       end # end repeat

      # body
      pdf.bounding_box([pdf.bounds.left, pdf.bounds.top - 75], :width  => pdf.bounds.width, :height => pdf.bounds.height - 100) do
        if @details.has_projects?
          @details.projects.each do |project|
            pdf.move_down 20
            pdf.text "<color rgb='#{@cloudwick_color}'><b>Project Name</b><color>: #{project.name}", inline_format: true
            pdf.table([
                ["<b>Client</b>", "#{project.client}"],
                ["<b>Title</b>", "#{project.title}"],
                ["<b>Duration</b>", "#{project.duration || 0}"],
                ["<b>Software Used</b>", "#{project.software.join(',')}"],
                ["<b>Management Tools</b>", "#{project.management_tools.join(',')}"],
                ["<b>Commercial Support</b>", "#{project.commercial_support.join(',')}"],
                ["<b>Point of Contanct</b>", "#{project.point_of_contact.empty? && 'None' || project.point_of_contact.join(',')}"],
              ],
              cell_style: {inline_format: true, borders: []},
              column_widths: [pdf.bounds.width/3, pdf.bounds.width - pdf.bounds.width/3],
              width: pdf.bounds.width
            )

            project_files_table = []
            # TODO Handle file uploads to s3 and provide link to download
            project.illustrations && project.illustrations.each do |illustartion|
              project_files_table << ["<link href='http://sync.cloudwick.com:9292/download/#{illustartion.file_id}'>#{illustartion.filename && illustartion.filename.split('_', 4).last}</link>", "illustration_type"]
            end

            project.projectdocuments && project.projectdocuments.each do |document|
              project_files_table << ["<link href='http://sync.cloudwick.com:9292/download/#{document.file_id}'>#{document.filename && document.filename.split('_', 4).last}</link>", "illustration_type"]
            end

            if !project_files_table.empty?
              pdf.move_down 10
              pdf.text "<b>#{project.name} project files</b>: (<i>click on the file name below to download</i>)", inline_format: true
              pdf.table(
                project_files_table,
                cell_style: {inline_format: true},
                column_widths: [pdf.bounds.width/2, pdf.bounds.width/2],
                width: pdf.bounds.width
              )
            end

            if project.has_usecases?
              project.usecases.each_with_index do |usecase, ui|
                pdf.move_down 10
                pdf.text "<b>Usecase #{ui + 1} Name</b>: #{usecase.name}", inline_format: true
                pdf.text "<b>Usecase #{ui + 1} Description</b>: #{usecase.description}", align: :justify, inline_format: true

                usecase.requirements && usecase.requirements.each_with_index do |requirement, ri|
                  pdf.move_down 10
                  pdf.text "<b>Requirement #{ri + 1} details</b>:", inline_format: true
                  pdf.table([
                      ["Description", "#{requirement.requirement}"],
                      ["Approach", "#{requirement.approch}"],
                      ["Effort", "#{requirement.effort}"],
                      ["TeamEffort", "#{requirement.teameffort}"],
                      ["Tools", "#{requirement.tools.join(', ')}"],
                      ["Resources", "#{requirement.resources}"],
                      ["Insights", "#{requirement.insights}"],
                      ["Benefits", "#{requirement.benefits}"],
                    ],
                    cell_style: {inline_format: true},
                    column_widths: [pdf.bounds.width/5, pdf.bounds.width - pdf.bounds.width/5],
                    width: pdf.bounds.width
                  )
                end
              end
            end
          end
        end
      end
      # footer for page numbers
      pdf.page_count.times do |i|
        pdf.go_to_page(i+1)
        pdf.bounding_box([pdf.bounds.left, pdf.bounds.bottom + 20], :width => pdf.bounds.width) {
          pdf.text "Page: #{i+1} / #{pdf.page_count}", :size => 10, align: :center, color: 'FFFFFF'
        }
      end
    end
  end # end build!
end
