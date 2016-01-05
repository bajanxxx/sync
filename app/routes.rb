module Sync
  module Routes
    autoload :Assets, 'app/routes/assets'
    autoload :Base, 'app/routes/base'
    autoload :Static, 'app/routes/static'

    autoload :Index, 'app/routes/index'

    autoload :Common, 'app/routes/common'

    autoload :Users, 'app/routes/users'
    autoload :Consultants, 'app/routes/consultants'
    autoload :ConsultantProjects, 'app/routes/consultant_projects'

    autoload :Jobs, 'app/routes/jobs'

    autoload :Campaigns, 'app/routes/campaigns'
    autoload :Vendors, 'app/routes/vendors'
    autoload :Customers, 'app/routes/customers'

    autoload :Documents, 'app/routes/documents'
    autoload :AirTickets, 'app/routes/air_tickets'
    autoload :Certifications, 'app/routes/certifications'
    autoload :CloudServers, 'app/routes/cloud_servers'

    autoload :Timesheets, 'app/routes/timesheets'
    autoload :TimesheetVendors, 'app/routes/timesheet_vendors'
    autoload :TimesheetClients, 'app/routes/timesheet_clients'
    autoload :TimesheetProjects, 'app/routes/timesheet_projects'
    autoload :TimesheetReports, 'app/routes/timesheet_reports'

    autoload :Training, 'app/routes/training'
    autoload :TrainingTracks, 'app/routes/training_tracks'
    autoload :TrainingTopics, 'app/routes/training_topics'
    autoload :TrainingIntegrations, 'app/routes/training_integrations'
    autoload :TrainingProjects, 'app/routes/training_projects'
    autoload :TrainingSubTopics, 'app/routes/training_sub_topics'
    autoload :TrainingAssignments, 'app/routes/training_assignments'
  end
end