module Sync
  module Helpers
    module DateTime
      # Gives back a list of dates from a week of specified date
      #
      # Usage:
      # dates_week(Date.today) { |d| d }
      def dates_week(d)
        (d.beginning_of_week...d.beginning_of_week+7).map{|a|
          yield a
        }
      end

      # time_ago_in_words(Time.now, 1.day.ago) # => 1 day
      # time_ago_in_words(Time.now, 1.hour.ago) # => 1 hour
      def time_ago_in_words(t1, t2)
        s = t1.to_i - t2.to_i # distance between t1 and t2 in seconds

        resolution = if s > 29030400 # seconds in a year
                       [(s/29030400), 'years']
                     elsif s > 2419200
                       [(s/2419200), 'months']
                     elsif s > 604800
                       [(s/604800), 'weeks']
                     elsif s > 86400
                       [(s/86400), 'days']
                     elsif s > 3600 # seconds in an hour
                       [(s/3600), 'hours']
                     elsif s > 60
                       [(s/60), 'minutes']
                     else
                       [s, 'seconds']
                     end

        # singular v. plural resolution
        if resolution[0] == 1
          resolution.join(' ')[0...-1]
        else
          resolution.join(' ')
        end
      end
    end
  end
end