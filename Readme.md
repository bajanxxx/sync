Cloudwick Sync
--------------

Central portal which manages

* Fetches jobs from several popular job portals like **DICE** and **INDEED**
* Manages job applications for all the consultants
* Central location for managing Cloudwick's Email Campaigning
* Document Request Management
* Manage (Create|Destroy|Upgrade|Start|Stop) cloud server's/cluster's both in public (AWS/RackSpace) adn in private (OpenStack) cloud environments.

Get it
------

> NOTE: Replace **[username]** in the following command with your github
> username as this is a private repository you should have access to read it.

```
cd /opt
git clone https://[username]@github.com/cloudwicklabs/sync.git
```

Install Dependencies:
--------------------

**Install Ruby 2.0.0:**

```
curl -L get.rvm.io | bash -s stable
source ~/.rvm/scripts/rvm || source /usr/local/rvm/scripts/rvm || source /etc/profile.d/rvm.sh
rvm requirements --verify-downloads 1
rvm install 2.0.0
rvm use 2.0.0 --default
rvm rubygems current
```

**Install Gem Dependencies:**

```
cd /opt/sync
rvm @global do bundle install
```

**Install External Dependencies:**

* [ImageMagick](http://www.imagemagick.org/script/binary-releases.php#unix)

Install MongoDB:
----------------
The following commands will install a single MongoDB instance on the local
system:

```
cd $HOME
curl -sO https://raw2.github.com/cloudwicklabs/scripts/master/mongo_install.sh
chmod +x mongo_install.sh
./mongo_install.sh
```

Configure it:
-------------
**Configuring Mongo**

You may have to configure `config/mongoid.yml` to specify where you are running the
mongo instance

**Configuring MailGun (for sending/receiving emails)**

Configure `config/config.yml` to specify Mail gun API keys and email addresses to use.

**Configuring new relic for monitoring**

Configure `config/newrelic.yml` to specify license_key.

**Configuring nginx web server:**

Copy `config/nginx.conf` to `/etc/nginx` and replace the path variables to reflect your environment.

Run it:
------
**Start unicorn application server:**

```
cd /opt/sync
RAILS_ENV='production' unicorn --config-file config/unicorn.rb --host 0.0.0.0 --port 9292 --env development --daemonize config.ru
# bundle exec rackup -s thin >> /var/log/sync.log 2>&1 &
```

**Starting Nginx web server:**

```
/etc/init.d/nginx start
```

**Starting 8 delayed_job processes:**

```
RAILS_ENV=production bin/delayed_job.rb -n 8 start
```

**stopping and restarting all processes**

```
cd /opt/sync
cat tmp/pids/unicorn.pid | xargs kill -QUIT
RAILS_ENV=production bin/delayed_job.rb stop
/etc/init.d/nginx stop

RAILS_ENV='production' unicorn --config-file config/unicorn.rb --host 0.0.0.0 --port 9292 --env development --daemonize config.ru
RAILS_ENV=production bin/delayed_job.rb -n 8 start
/etc/init.d/nginx start
```

**Creating indexes for collections** (Onetime)

```
rake mongoid:create_customer_indexes
rake mongoid:create_job_indexes
rake mongoid:create_vendor_indexes
rake mongoid:create_tracking_indexes
rake mongoid_search:index
rake jobs:create_indexes
```

Initialize the fetcher to get a decent amount of posts to work with, its not
required to run the fetcher unless you want the data right away:

```
ruby /opt/sync/fetch_job_postings.rb \
  --search hadoop \
  --age-of-postings 5 \
  --traverse-depth 30 \
  --page-search CON_CORP
ruby /opt/sync/fetch_job_postings.rb \
  --search cassandra \
  --age-of-postings 5 \
  --traverse-depth 30 \
  --page-search CON_CORP
ruby /opt/sync/fetch_indeed_postings.rb \
  --search hadoop \
  --age-of-postings 5 \
  --limit 1000
ruby /opt/sync/fetch_indeed_postings.rb \
  --search cassandra \
  --age-of-postings 5 \
  --limit 1000
```

Create the following cron job's for the fetcher to run continuously & also to backup mongo:

```
# dice
0 9 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_job_postings.rb --search hadoop --age-of-postings 1 --traverse-depth 25 --page-search CON_CORP >> /var/log/sync_fetcher.log 2>&1
0 0-23/2 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_job_postings.rb --search hadoop --age-of-postings 1 --traverse-depth 1 --page-search CON_CORP >> /var/log/sync_fetcher.log 2>&1
0 9 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_job_postings.rb --search cassandra --age-of-postings 1 --traverse-depth 25 --page-search CON_CORP >> /var/log/sync_fetcher.log 2>&1
0 0-23/2 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_job_postings.rb --search cassandra --age-of-postings 1 --traverse-depth 1 --page-search CON_CORP >> /var/log/sync_fetcher.log 2>&1
# indeed
10 9 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_indeed_postings.rb --search hadoop --age-of-postings 1 --limit 1000 >> /var/log/sync_fetcher.log 2>&1
10 0-23/2 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_indeed_postings.rb --search hadoop --age-of-postings 1 --limit 100 >> /var/log/sync_fetcher.log 2>&1
10 9 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_indeed_postings.rb --search cassandra --age-of-postings 1 --limit 1000 >> /var/log/sync_fetcher.log 2>&1
10 0-23/2 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/fetch_indeed_postings.rb --search cassandra --age-of-postings 1 --limit 100 >> /var/log/sync_fetcher.log 2>&1
# mongo backup
0 0 * * * /bin/bash /opt/sync/backup_mongo.sh -p "/mongo-backup-100 /mongo-backup-217" -d sync >> /var/log/sync_backup.log 2>&1
# cloud server bootstrapper
*/5 * * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/sync/cloud_instances.rb >> /var/log/sync_cloud_bootstrapper.log 2>&1
```

License and Authors
-------------------

Authors: [Ashrith](http://github.com/ashrithr)

Copyright: 2013, Cloudwick Inc

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
