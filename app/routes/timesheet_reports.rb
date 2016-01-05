module Sync
  module Routes
    class TimesheetReports < Base
      get '/timesheets/reports/:year/:month' do |year, month|
        protected!

        data = {}
        _debug = {}
        start_date = Date.new(year.to_i, month.to_i - 1, -5)
        end_date = Date.new(year.to_i, month.to_i, -1)

        Consultant.all.each do |_consultant|
          _total = 0.0
          _debug[_consultant.email.to_sym] = []

          Timesheet.where(consultant: _consultant.email, week: start_date..end_date).each do |entry|
            entry.timesheet_details.each do |td|
              if td.workday >= Date.new(year.to_i, month.to_i) && td.workday <= Date.new(year.to_i, month.to_i, -1)
                _debug[_consultant.email.to_sym] << { day: td.workday, hours: td.hours }
                _total += td.hours
              end
            end
          end

          data[_consultant.email.to_sym] = _total
        end

        erb :timesheets_reports, locals: {
          data: data,
          year: year,
          month: month
        }
      end
    end
  end
end
