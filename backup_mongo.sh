#!/bin/bash
#
# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Back's up mongodb to specified directory paths
#
# Copyright 2013-2015, Cloudwick, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

### !!! DONT CHANGE BEYOND THIS POINT. DOING SO MAY BREAK THE SCRIPT !!!
declare destination_dirs
declare database_name
declare aws_access_key

function check_for_root () {
  if [ "$(id -u)" != "0" ]; then
   print_error "Please run with super user privileges."
   exit 1
  fi
}

function check_preqs () {
  check_for_root

  for command in tar mongodump; do
    type -P $command &> /dev/null || {
      echo "Command $command not found"
      echo "Aborting!!!"
      exit 1
    }
  done

  if [[ ! -z $aws_s3_bucket ]]; then
    type -P aws &> /dev/null || {
      echo "Command 'aws' is required, please install aws command line tools to backup to s3"
      echo "Aborting!!!"
      exit 1
    }

    if [[ ! -f $HOME/.aws/credentials  ]]; then
      echo "AWS credentials file is not found, please run 'aws configure' command to generate the credentials file"
      echo "Aborting!!!"
      exit 1
    fi
  fi
}

function backup_now () {
  local archive_name="$1"
  local dest_dirs=$destination_dirs
  local db=$database_name
  local options=""
  local staging_dir="/tmp/mongo_backup_staging"
  if [[ ! -d $staging_dir ]]; then
    mkdir $staging_dir
  fi
  echo "Backing up data to ${archive_name}"

  if [[ -n "$db" ]]; then
    options="$options --db $db"
  fi

  # Dump the database
  mongodump --out $staging_dir/$file_name $options

  # Tar Gzip the file
  tar -C $staging_dir/ -zcvf $staging_dir/$archive_name $file_name/

  # Remove the backup directory
  rm -r $staging_dir/$file_name

  for dest_dir in $dest_dirs; do
    if [[ ! -d $dest_dir ]]; then
      mkdir -p $dest_dir
    fi
    cp $staging_dir/$archive_name $dest_dir
  done
}

function backup_to_s3 () {
  local archive_name="$1"
  local dest_dirs=$destination_dirs
  local dest_dir=$(echo $dest_dirs | { read first rest; echo $first ;})

  echo "Backing up MongoDB to S3..."
  aws s3 cp $dest_dir/$archive_name $aws_s3_bucket --region=$aws_s3_region
}

function usage () {
  script=$0
  cat <<USAGE
Syntax
`basename ${script}` -d {DEST_DIRS} -h

-p: destination directories
-d: database name
-b: aws bucket name
-r: aws region name
-h: show this message

Example:
`basename ${script}` -p "/mongo_backup1 /mongo_backup2" -d database_name
`basename ${script}` -p /mongo_backup -d database_name
`basename ${script}` -p /mongo_backup -d database_name -b s3://cloudwicklabs.sync/mongo_backup/ -r us-west-1

USAGE
  exit 1
}


export PATH="$PATH:/usr/local/bin"
while getopts "p:d:k:s:b:r:h" opts
do
  case $opts in
    d)
      database_name=$OPTARG
      ;;
    p)
      destination_dirs=$OPTARG
      ;;
    b)
      aws_s3_bucket=$OPTARG
      ;;
    r)
      aws_s3_region=$OPTARG
      ;;
    h)
      usage
      ;;
    \?)
      usage
      ;;
  esac
done

if [[ -z $database_name ]] || [[ -z $destination_dirs ]]; then
  usage
  exit 1
fi

# Store the current date in YYYY-mm-DD-HHMMSS
date=$(date -u "+%F-%H%M%S")
file_name="backup-$date"
archive_name="$file_name.tar.gz"

check_preqs
backup_now $archive_name

if [[ ! -z $aws_s3_bucket ]]; then
  echo "Backing upto s3 (path: $aws_s3_bucket, region: $aws_s3_region)"
  backup_to_s3 $archive_name
fi