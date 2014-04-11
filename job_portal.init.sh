#!/bin/bash

#
# Start up script to start/stop/restart job_portal using rack
#

# Get the script's path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG="/var/log/job_portal.log"
PROCESS_NAME="rackup"

function start () {
  if ps aux | grep -v grep | grep -v $0 | grep $PROCESS_NAME > /dev/null; then
    echo "Service ${PROCESS_NAME} is already running... skipping."
  else
    echo "Starting ${PROCESS_NAME} ..."
    cd $DIR && bundle exec rackup -s thin >> $LOG 2>&1 &
    echo "Starting ${PROCESS_NAME} ... [DONE]"
  fi
}

function status () {
  if ps aux | grep -v grep | grep -v $0 | grep $PROCESS_NAME > /dev/null; then
    echo "Service ${PROCESS_NAME} is running..."
  else
    echo "Service ${PROCESS_NAME} is not running!!!"
  fi
}

function stop () {
  if ps aux | grep -v grep | grep -v $0 | grep $PROCESS_NAME > /dev/null; then
    echo "Stopping ${PROCESS_NAME} ..."
    kill $(ps aux | grep -v grep | grep -v $0 | grep $PROCESS_NAME | awk '{print $2}')
    echo "Stopping ${PROCESS_NAME} ... [DONE]"
  else
    echo "Service ${PROCESS_NAME} is not running"
  fi
}

function restart () {
  stop
  start
}

if [[ $# -ne 1 ]]; then
  echo "Argument required."
  echo "Usage: `basename $0` start|stop|restart"
  exit
fi

case $1 in
  'start')
    start
    ;;
  'stop')
    stop
    ;;
  'restart')
    restart
    ;;
esac
