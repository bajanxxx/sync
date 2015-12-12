# Cloudwick Sync

Central portal featuring:

* Job Portal
  * Fetches jobs from several popular job portals like **DICE** and **INDEED**
  * Manages job applications for all the consultants
* Email Campaigning Portal
  * Central location for managing Cloudwick's Email Campaigning
* Consultant Requests Portal
  * Document Request Management
  * Certification Request Management
  * Air tickets request management
  * Cloud servers request management
* Training Portal
  * Trainer/Trainee Portal for accessing and tracking trainee progress

# Get it

> NOTE: Replace **[username]** in the following command with your github
> username as this is a private repository you should have access to read it.

```
cd /opt
git clone https://[username]@github.com/cloudwicklabs/sync.git
```

# Install Dependencies:

### Install Ruby 2.0.0 using rbenv

```
yum install -y git-core zlib zlib-devel gcc-c++ patch readline readline-devel libyaml-devel \
    libffi-devel openssl-devel make bzip2 autoconf automake libtool bison curl sqlite-devel
cd
git clone git://github.com/sstephenson/rbenv.git .rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
exec $SHELL

git clone git://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bash_profile
exec $SHELL

rbenv install -v 2.1.6
rbenv global 2.1.6
gem install bundle
echo "gem: --no-document" > ~/.gemrc
```

### Install External Dependencies

* [ImageMagick](http://www.imagemagick.org/script/binary-releases.php#unix)

> Redhat: `yum -y install ImageMagick ImageMagick-devel`
> Ubuntu: `apt-get install libmagickwand-dev imagemagick`

### Install Gem Dependencies

```
cd /opt/sync
bundle install
rbenv rehash
```

## Install MongoDB:

The following commands will install a single MongoDB instance on the local system 
(this will by default install mongo v2.4.9):

```
cd
curl -sO https://raw.githubusercontent.com/cloudwicklabs/scripts/master/mongo_install.sh
chmod +x mongo_install.sh
./mongo_install.sh
```

## Install Nginx:

```
cat > /etc/yum.repos.d/nginx.repo <<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/6/$basearch/
gpgcheck=0
enabled=1
EOF

yum install -y nginx
```

## Install memcached:

```
yum install -y memcached.x86_64
```

# Configure it:

**Configuring Mongo**

You may have to configure `config/mongoid.yml` to specify where you are running the
mongo instance

**Configuring MailGun (for sending/receiving emails)**

Configure `config/config.yml` to specify Mail gun API keys and email addresses to use.

**Configuring nginx web server:**

Copy `config/nginx.conf` to `/etc/nginx` and replace the path variables to reflect your environment.

**Configure memcached**

```
cat > /etc/sysconfig/memcached <<EOF
PORT="11211"
USER="memcached"
MAXCONN="1024"
CACHESIZE="1024"
OPTIONS="-l IP_ADDRESS"
EOF
```

> configure CACHESIZE according to your system configuration in this case its 1GB.
> configure OPTIONS replace `IP_ADDRESS` with your system public IP address.

# Run it:

**Rake task to build SpRockets**

```
RACK_ENV=production rake assets:precompile
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

**One script to start it all:**

```
bin/sync_init.sh start all
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
# every midnight 12 am deep fetch
25 0 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice deep hadoop >> /var/log/dice_deep_hadoop_fetcher.log 2>&1
35 0 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice deep cassandra >> /var/log/dice_deep_cassandra_fetcher.log 2>&1
45 0 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice deep spark >> /var/log/dice_deep_spark_fetcher.log 2>&1
# every morning 9 am daily fetch
0 9 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice daily hadoop >> /var/log/dice_daily_hadoop_fetcher.log 2>&1
10 9 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice daily cassandra >> /var/log/dice_daily_cassandra_fetcher.log 2>&1
20 9 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice daily spark >> /var/log/dice_daily_spark_fetcher.log 2>&1
# ever even hours hourly fetch
0 */2 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice hourly hadoop >> /var/log/dice_hourly_hadoop_fetcher.log 2>&1
10 */2 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice hourly cassandra >> /var/log/dice_hourly_hadoop_fetcher.log 2>&1
20 */2 * * * /bin/bash /opt/sync/bin/start_start_fetcher.sh dice hourly spark >> /var/log/dice_hourly_hadoop_fetcher.log 2>&1
# old
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

# License and Authors

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
