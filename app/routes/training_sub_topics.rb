module Sync
  module Routes
    class TrainingSubTopics < Base
      # Render sub topic
      get '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid' do |trackid, topicid, subtopicid|
        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        consultant = Consultant.find(@session_username)
        sub_topic = topic.training_sub_topics.find(subtopicid)

        if !(@user.administrator? || @user.owner?) && !user_access_to_subtopic(consultant, track, topic, sub_topic)
          erb :training_sub_topic_noaccess, locals: {
              track: track,
              topic: topic,
              sub_topic: sub_topic
          }
        else
          slides_count =  if sub_topic.content_thumbnails
                            sub_topic.content_thumbnails.count
                          else
                            0
                          end
          slide =   if sub_topic.content_slides.find_by(name: "first")
                      Base64.encode64(download_file(sub_topic.content_slides.find_by(name: "first").file_id).read)
                    else
                      nil
                    end
          uploaded =  if sub_topic.pdf_file
                        "#{time_ago_in_words(Time.now, sub_topic.pdf_file.uploaded_date)} ago"
                      else
                        'N/A'
                      end
          total_assignments = sub_topic.training_assignments.count
          assignment_submissions = 0
          assignments_approved = 0
          sub_topic.training_assignments.each do |assignment|
            assignment_submissions += assignment.training_assignment_submissions.where(consultant_id: @session_username, status: 'SUBMITTED').count
          end
          sub_topic.training_assignments.each do |assignment|
            assignments_approved += assignment.training_assignment_submissions.where(consultant_id: @session_username, status: 'APPROVED').count
          end

          erb :training_sub_topic, locals: {
              track: track,
              topic: topic,
              sub_topic: sub_topic,
              slides_count: slides_count,
              slide: slide,
              uploaded: uploaded,
              views: sub_topic.views,
              presentation_status: sub_topic.state,
              total_assignments: total_assignments,
              assignment_submissions: assignment_submissions,
              assignments_approved: assignments_approved
          }
        end
      end

      # Creates a new subtopic for a specified topic of a track
      post '/training/track/:trackid/topic/:topicid/subtopic/create' do |trackid, topicid|
        sub_topic_name = params[:tname]
        et_topic = params[:et]
        order = params[:order]

        if et_topic.to_i > 180
          success = false
          message = "It's not recommended to put sub topics greater than 3 hours"
        else
          TrainingTopic.find(topicid).training_sub_topics.find_or_create_by(
              name: sub_topic_name,
              et: et_topic.to_i,
              order: order.to_i
          )
          success    = true
          message    = "Successfully added new training sub topic #{sub_topic_name}"

          flash[:info] = message
        end

        { success: success, msg: message }.to_json
      end

      # Deletes a specified subtopic
      post '/training/track/:trackid/topic/:topicid/subtopic/delete/:subtopicid' do |trackid, topicid, subtopicid|
        sub_topic = TrainingSubTopic.find(subtopicid)
        if sub_topic
          content_slide_files = []
          content_thumbnail_files = []

          if sub_topic.pdf_file.respond_to?(:file_id)
            grid_file = sub_topic.pdf_file.file_id
            grid.delete(BSON::ObjectId(grid_file)) if grid_file
            sub_topic.content_slides.each do |slide|
              content_slide_files << slide.file_id if slide.respond_to?(:file_id)
            end
            unless content_slide_files.empty?
              content_slide_files.each do |slide_file|
                grid.delete(BSON::ObjectId(slide_file)) if slide_file
              end
            end
            sub_topic.content_thumbnails.each do |thumb|
              content_thumbnail_files << thumb.file_id if thumb.respond_to?(:file_id)
            end
            unless content_thumbnail_files.empty?
              content_thumbnail_files.each do |thumb_file|
                grid.delete(BSON::ObjectId(thumb_file)) if thumb_file
              end
            end
            sub_topic.content_slides.delete_all
            sub_topic.content_thumbnails.delete_all
            sub_topic.pdf_file.delete
          end
          sub_topic.delete
        end
      end

      # admin page for uploading & managing slides deck to a subtopic
      get '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/admin' do |trackid, topicid, subtopicid|
        protected!

        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        sub_topic = topic.training_sub_topics.find(subtopicid)
        erb :training_sub_topic_admin, locals: {
            track: track,
            topic: topic,
            sub_topic: sub_topic
        }
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/unlink' do |trackid, topicid, subtopicid|
        success    = true
        message    = "Successfully unlinked and deleted file"

        sub_topic = TrainingSubTopic.find(subtopicid)
        if sub_topic
          content_slide_files = []
          content_thumbnail_files = []

          if sub_topic.pdf_file.respond_to?(:file_id)
            grid_file = sub_topic.pdf_file.file_id
            grid.delete(BSON::ObjectId(grid_file)) if grid_file
            sub_topic.content_slides.each do |slide|
              content_slide_files << slide.file_id if slide.respond_to?(:file_id)
            end
            unless content_slide_files.empty?
              content_slide_files.each do |slide_file|
                grid.delete(BSON::ObjectId(slide_file)) if slide_file
              end
            end
            sub_topic.content_thumbnails.each do |thumb|
              content_thumbnail_files << thumb.file_id if thumb.respond_to?(:file_id)
            end
            unless content_thumbnail_files.empty?
              content_thumbnail_files.each do |thumb_file|
                grid.delete(BSON::ObjectId(thumb_file)) if thumb_file
              end
            end
            sub_topic.content_slides.delete_all
            sub_topic.content_thumbnails.delete_all
            sub_topic.pdf_file.delete
          end
        end

        sub_topic.update_attributes(file: 'NIL')

        { success: success, msg: message }.to_json
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/references' do |trackid, topicid, subtopicid|
        success    = true
        message    = "Successfully updated references"

        sub_topic = TrainingSubTopic.find(subtopicid)
        references = params[:references]

        sub_topic.update_attributes(
            references: references
        )

        { success: success, msg: message }.to_json
      end

      # Upload presentation and convert presentation pdf to images
      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/upload' do |trackid, topicid, subtopicid|
        file = params[:pdf][:tempfile]
        file_name = params[:pdf][:filename]
        file_type = params[:pdf][:type]
        file_id = upload_file(file, file_name)

        topic = TrainingTopic.find(topicid)
        sub_topic = topic.training_sub_topics.find(subtopicid)

        if file_id
          sub_topic.pdf_file = PdfFile.create(
              file_id: file_id,
              filename: file_name,
              uploaded_date: DateTime.now,
              type: file_type
          )
          sub_topic.update_attributes!(file: 'LINKED')
          Delayed::Job.enqueue(
              ConvertPdfToImages.new(sub_topic, file_id, @settings),
              queue: 'pdf_convertions',
              priority: 10,
              run_at: 5.seconds.from_now
          )
          puts "Uploaded successfully #{file_id}"
          flash[:info] = "Successfully uploaded presentation '#{file_id}'"
        else
          puts "Failed uploading pdf. pdf with #{file_name} already exists!."
          flash[:warning] = "Failed uploading presentation. Presentation with name '#{file_name}' already exists!."
        end
        redirect back
      end

      # start slide show
      get '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/ss' do |trackid, topicid, subtopicid|
        topic = TrainingTopic.find(topicid)
        sub_topic = topic.training_sub_topics.find(subtopicid)
        total_slides = sub_topic.content_slides.count

        # increment the views on this presentation by 1
        sub_topic.inc(:views, 1)
        # store detail visit for this presentation
        TrainingPresetationView.create(
            track: trackid,
            topic: topicid,
            subtopic: subtopicid,
            consultant: @session_username
        )

        thumbnails = []

        total_slides.times do |_sid|
          if _sid.to_i == 0
            slide_id = "first"
          elsif _sid.to_i == total_slides - 1
            slide_id = "last"
          else
            slide_id = _sid
          end

          thumbnails << {
              name: slide_id,
              data: Base64.encode64(download_file(sub_topic.content_thumbnails.find_by(name: slide_id).file_id).read)
          }
        end

        erb :slider,
            layout: :layout_slider,
            locals: {
                slides_count: total_slides,
                thumbnails: thumbnails,
                trackid: trackid,
                tid: topicid,
                stid: subtopicid
            }
      end

      # render individual slides
      get '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/ss/:slideid' do |trackid, topicid, subtopicid, slideid|
        topic = TrainingTopic.find(topicid)
        sub_topic = topic.training_sub_topics.find(subtopicid)
        total_slides = sub_topic.content_slides.count

        if slideid == "0"
          slide_id = "first"
        elsif slideid == (total_slides-1).to_s
          slide_id = "last"
        else
          slide_id = params[:slideid]
        end
        _sid = sub_topic.content_slides.find_by(name: slide_id).file_id

        image_file = download_file(_sid).read
        erb :slide,
            layout: :layout_slider,
            locals: {
                image_contents: Base64.encode64(image_file)
            }
      end

      get '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/:consultant/scratchpad' do |trackid, topicid, subtopicid, consultant|
        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        sub_topic = topic.training_sub_topics.find(subtopicid)
        sp = sub_topic.training_scratch_pads.find_or_create_by(consultant_id: consultant)

        erb :training_sub_topic_scratchpad,
            locals: {
                track: track,
                topic: topic,
                sub_topic: sub_topic,
                consultant: consultant,
                sp: sp
            }
      end

      post '/training/track/:trackid/topic/:topicid/subtopic/:subtopicid/:consultant/scratchpad' do |_, _, subtopicid, consultant|
        success = true
        message = 'successfully saved scratchpad contents'

        data = params[:content]

        sub_topic = TrainingSubTopic.find(subtopicid)
        sp = sub_topic.training_scratch_pads.find_by(consultant_id: consultant)
        sp.update_attributes(contents: data, last_saved_at: DateTime.now)

        { success: success, msg: message }.to_json
      end
    end
  end
end