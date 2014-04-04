Job Portal
----------

Interface to make the life of our HR Teams better.

Get it
------

> NOTE: Replace **[username]** in the following command with your github
> username as this is a private repository you should have access to read it.

```
cd /opt
git clone https://[username]@github.com/cloudwicklabs/job_portal.git
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
cd /opt/job_portal && bundle install
```

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
You may have to configure `mongoid.yml` to specify where you are running the
mongo instance

Run it:
------
**Start a web server:**

```
cd /opt/job_portal
bundle exec rackup -s thin >> /var/log/job_portal.log 2>&1 &
```

Initialize the fetcher to get a decent amount of posts to work with, its not
required to run the fetcher unless you want the data right away:

```
ruby /opt/job_portal/fetch_job_postings.rb \
  --search hadoop \
  --age-of-postings 5 \
  --traverse-depth 30 \
  --page-search CON_CORP
ruby /opt/job_portal/fetch_job_postings.rb \
  --search cassandra \
  --age-of-postings 5 \
  --traverse-depth 30 \
  --page-search CON_CORP
```

Create a cron job for the fetcher to run continuously:

```
0 9 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/job_portal/fetch_job_postings.rb --search hadoop --age-of-postings 1 --traverse-depth 25 --page-search CON_CORP >> /var/log/job_portal_fetcher.log 2>&1
0 0-23/2 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/job_portal/fetch_job_postings.rb --search hadoop --age-of-postings 1 --traverse-depth 1 --page-search CON_CORP >> /var/log/job_portal_fetcher.log 2>&1
0 9 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/job_portal/fetch_job_postings.rb --search cassandra --age-of-postings 1 --traverse-depth 25 --page-search CON_CORP >> /var/log/job_portal_fetcher.log 2>&1
0 0-23/2 * * * /usr/local/rvm/wrappers/ruby-2.0.0-*@global/ruby /opt/job_portal/fetch_job_postings.rb --search cassandra --age-of-postings 1 --traverse-depth 1 --page-search CON_CORP >> /var/log/job_portal_fetcher.log 2>&1
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
