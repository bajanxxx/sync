module Sync
  module Routes
    class TrainingTopics < Base
      # Render topic page for a specified track
      get '/training/track/:trackid/topic/:topicid' do |trackid, topicid|
        track = TrainingTrack.find(trackid)
        topic = TrainingTopic.find(topicid)
        consultant = Consultant.find(@session_username)

        if @user.owner? || @user.administrator? || @user.trainer?
          order = if topic.training_sub_topics.count == 0
                    1
                  else
                    topic.training_sub_topics.desc(:order).limit(1).first.order + 1
                  end

          erb :training_topic, locals: {
              track: track,
              topic: topic,
              assignable_sub_topic_order: order
          }
        else
          if user_access_to_topic(consultant, track, topic)
            erb :training_topic, locals: {
                track: track,
                topic: topic,
                assignable_sub_topic_order: 0 # just a place holder
            }
          else
            erb :training_topic_noaccess, locals: {
                track: track,
                topic: topic
            }
          end
        end
      end

      # return back topics of a specified track
      get '/training/track/:trackcode/topics' do |trackcode|
        topics = TrainingTrack.find_by(code: trackcode).training_topics
        values = []

        topics.each do |t|
          values << t.name
        end

        if request.xhr?
          halt 200, values.to_json
        else
          values.to_json
        end
      end

      # Create a new topic in a specified track
      post '/training/track/:trackid/topic/create' do |trackid|
        topic_name = params[:tname]
        topic_code = params[:tcode]
        email = params[:email]
        category = params[:category]
        order = params[:order]

        success = true

        %w(tname tcode email category).each do |param|
          if params[param.to_sym].empty?
            success = false
            message = "Field '#{param}' cannot be empty"
          end
          return { success: success, msg: message }.to_json unless success
        end

        if email !~ @email_regex
          success = false
          message = "email not formatted properly"
        end

        if topic_code.length > 10
          success = false
          message = "Training topic short code exceeds 10 characters"
        end

        if TrainingTrack.find(trackid).training_topics.find_by(code: topic_code)
          success = false
          message = "Training Topic with code #{topic_code} already exists, please choose another code"
        end

        if success
          track = TrainingTrack.find(trackid)
          track.training_topics.create(
              code: topic_code,
              name: topic_name,
              contact: email,
              category: category
          )

          message = "Successfully added new training topic #{topic_name} to track #{track.code}"
          flash[:info] = message
        end

        { success: success, msg: message }.to_json
      end

      # Delete a topic from a specified track
      post '/training/track/:trackid/topic/delete/:topicid' do |trackid, topicid|
        topic = TrainingTopic.find(topicid)
        if topic.training_sub_topics.count == 0
          topic.delete
        else
          flash[:warning] = 'There are sub topics in the topic you are trying to delete!'
        end
      end

    end
  end
end