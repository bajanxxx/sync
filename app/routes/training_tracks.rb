module Sync
  module Routes
    class TrainingTracks < Base
      # Render specific training track page
      get '/training/track/:tid' do |tid|
        track = TrainingTrack.find(tid)
        if @user.administrator?
          file = File.read(File.expand_path("../../assets/data/certifications.json", __FILE__))
          c_hash = JSON.parse(file)
          erb :training_track, locals: {
              track: track,
              preqs: track.training_topics.where(category: 'P').asc(:order),
              core: track.training_topics.where(category: 'C').asc(:order),
              adv: track.training_topics.where(category: 'A').asc(:order),
              opt: track.training_topics.where(category: 'O').asc(:order),
              c_hash: c_hash,
              access: { preq: true, core: true, adv: true, opt: true, certs: true } # just a place holder
          }
        else
          consultant = Consultant.find(@session_username)
          if consultant.details.training_tracks.include?(track.code)
            erb :training_track, locals: {
                track: track,
                preqs: track.training_topics.where(category: 'P').asc(:order),
                core: track.training_topics.where(category: 'C').asc(:order),
                adv: track.training_topics.where(category: 'A').asc(:order),
                opt: track.training_topics.where(category: 'O').asc(:order),
                access: user_track_access_breakdown(consultant, track)
            }
          else
            erb :training_track_noaccess, locals: {
                track: track
            }
          end
        end
      end

      # Creates a new training track
      post '/training/track/create' do
        track_name = params[:tname]
        short_code = params[:tcode]

        success    = true
        message    = "Successfully added new training track #{short_code}"

        if TrainingTrack.find_by(code: short_code)
          success = false
          message = "Training Track with code #{short_code} already exists, please choose another code"
        end

        if success
          TrainingTrack.create(
              code: short_code,
              name: track_name
          )

          flash[:info] = message
        end

        { success: success, msg: message }.to_json
      end

      # Associates a specific certification to a track
      post '/training/track/:trackid/associate/certification' do |trackid|
        cert = params[:cert]

        success = true
        message = 'Successfully associated certification to topic'

        track = TrainingTrack.find(trackid)

        if track.certifications.include?(cert)
          message = 'Cert already associated, ignoring!'
        else
          track.push(:certifications, cert)
        end
        { success: success, msg: message }.to_json
      end
    end
  end
end