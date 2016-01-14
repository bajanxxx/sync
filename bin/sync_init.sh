#!/bin/bash

#
# Start up script to start/stop/restart job_portal using rack
#

# Get the script's path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
echo "Working DIR: ${DIR}"
LOG="/var/log/job_portal.log"
BIND_IP="127.0.0.1"
BIND_PORT="9292"
UNICORN_PROCESS="unicorn"
DELAYEDJOB_PROCESS="delayed_job"
DELAYEDJOB_PROCESS_COUNT=8
NGINX_PROCESS="nginx"
MEMCACHED_PROCESS="memcached"
ENVIRONMENT="production"


function start_unicorn () {
  #if ps aux | grep -v grep | grep -v $0 | grep ${UNICORN_PROCESS} > /dev/null; then
  if [[ -f tmp/pids/unicorn.pid ]]; then
    echo "Service ${UNICORN_PROCESS} is already running... skipping."
  else
    echo "Starting ${UNICORN_PROCESS} in ${ENVIRONMENT} environment..."
    cd $DIR && RACK_ENV=${ENVIRONMENT} ${UNICORN_PROCESS} --config-file config/unicorn.rb --host ${BIND_IP} --port ${BIND_PORT} --env ${ENVIRONMENT} --daemonize config.ru >> $LOG 2>&1
    echo "Starting ${UNICORN_PROCESS} ... [DONE]"
  fi
}

function status_unicorn () {
  if ps aux | grep -v grep | grep -v $0 | grep ${UNICORN_PROCESS} > /dev/null; then
    echo "Service ${UNICORN_PROCESS} is running..."
  else
    echo "Service ${UNICORN_PROCESS} is not running!!!"
  fi
}

function stop_unicorn () {
#  if ps aux | grep -v grep | grep -v $0 | grep ${UNICORN_PROCESS} > /dev/null; then
  if [[ -f tmp/pids/unicorn.pid ]]; then
    echo "Stopping ${UNICORN_PROCESS} ..."
    cd $DIR && cat tmp/pids/unicorn.pid | xargs kill -QUIT
    echo "Stopping ${UNICORN_PROCESS} ... [DONE]"
  else
    echo "Service ${UNICORN_PROCESS} is not running"
  fi
}

function restart_unicorn () {
  stop_unicorn
  sleep 5
  start_unicorn
}

function start_delayedjob () {
  if ps aux | grep -v grep | grep -v $0 | grep -v log | grep ${DELAYEDJOB_PROCESS} > /dev/null; then
    echo "Service ${DELAYEDJOB_PROCESS} is already running... skipping."
  else
    echo "Starting ${DELAYEDJOB_PROCESS} in ${ENVIRONMENT} environment..."
    cd $DIR && RAILS_ENV=${ENVIRONMENT} bin/delayed_job.rb -n ${DELAYEDJOB_PROCESS_COUNT} start >> $LOG 2>&1
    echo "Starting ${DELAYEDJOB_PROCESS} ... [DONE]"
  fi
}

function stop_delayedjob () {
  if ps aux | grep -v grep | grep -v $0 | grep -v log | grep ${DELAYEDJOB_PROCESS} > /dev/null; then
    echo "Stopping ${DELAYEDJOB_PROCESS} ..."
    cd $DIR && RAILS_ENV=${ENVIRONMENT} bin/delayed_job.rb -n ${DELAYEDJOB_PROCESS_COUNT} stop >> $LOG 2>&1
    echo "Stopping ${DELAYEDJOB_PROCESS} ... [DONE]"
  else
    echo "Service ${DELAYEDJOB_PROCESS} is not running"
  fi
}

function status_delayedjob () {
  if ps aux | grep -v grep | grep -v $0 | grep -v log | grep ${DELAYEDJOB_PROCESS} > /dev/null; then
    echo "Service ${DELAYEDJOB_PROCESS} is running..."
  else
    echo "Service ${DELAYEDJOB_PROCESS} is not running!!!"
  fi
}

function restart_delayedjob () {
  stop_delayedjob
  sleep 5
  start_delayedjob
}

function start_nginx () {
  if ps aux | grep -v grep | grep -v $0 | grep ${NGINX_PROCESS} > /dev/null; then
    echo "Service ${NGINX_PROCESS} is already running... skipping."
  else
    echo "Starting ${NGINX_PROCESS} in ${ENVIRONMENT} environment..."
    service nginx start >> $LOG 2>&1
    echo "Starting ${NGINX_PROCESS} ... [DONE]"
  fi
}

function stop_nginx () {
  if ps aux | grep -v grep | grep -v $0 | grep ${NGINX_PROCESS} > /dev/null; then
    echo "Stopping ${NGINX_PROCESS} ..."
    service nginx stop >> $LOG 2>&1
    echo "Stopping ${NGINX_PROCESS} ... [DONE]"
  else
    echo "Service ${NGINX_PROCESS} is not running"
  fi
}

function status_nginx () {
  if ps aux | grep -v grep | grep -v $0 | grep ${NGINX_PROCESS} > /dev/null; then
    echo "Service ${NGINX_PROCESS} is running..."
  else
    echo "Service ${NGINX_PROCESS} is not running!!!"
  fi
}

function restart_nginx () {
  stop_nginx
  sleep 5
  start_nginx
}

function start_memcached () {
  if ps aux | grep -v grep | grep -v $0 | grep ${MEMCACHED_PROCESS} > /dev/null; then
    echo "Service ${MEMCACHED_PROCESS} is already running... skipping."
  else
    echo "Starting ${MEMCACHED_PROCESS} in ${ENVIRONMENT} environment..."
    service memcached start >> $LOG 2>&1
    echo "Starting ${MEMCACHED_PROCESS} ... [DONE]"
  fi
}

function stop_memcached () {
  if ps aux | grep -v grep | grep -v $0 | grep ${MEMCACHED_PROCESS} > /dev/null; then
    echo "Stopping ${MEMCACHED_PROCESS} ..."
    service memcached stop >> $LOG 2>&1
    echo "Stopping ${MEMCACHED_PROCESS} ... [DONE]"
  else
    echo "Service ${MEMCACHED_PROCESS} is not running"
  fi
}

function status_memcached () {
  if ps aux | grep -v grep | grep -v $0 | grep ${MEMCACHED_PROCESS} > /dev/null; then
    echo "Service ${MEMCACHED_PROCESS} is running..."
  else
    echo "Service ${MEMCACHED_PROCESS} is not running!!!"
  fi
}

function restart_memcached () {
  stop_memcached
  sleep 5
  start_memcached
}

if [[ $# -ne 2 ]]; then
  echo "Argument required."
  echo "Usage: `basename $0` start|stop|restart all"
  echo "  all -> start|stop|restart unicorn, nginx, dj, memcached"
  echo "Usage: `basename $0` start|stop|restart web"
  echo "  web -> start|stop|restart unicorn, nginx, memcached"
  echo "Usage: `basename $0` start|stop|restart unicorn"
  echo "  web -> start|stop|restart unicorn"
  echo "Usage: `basename $0` start|stop|restart dj"
  echo "  dj -> start|stop|restart dj"
  exit
fi

case $1 in
  'start')
    case $2 in
      'all')
        start_unicorn
        start_delayedjob
        start_nginx
        start_memcached
        ;;
      'web')
        start_unicorn
        start_nginx
        start_memcached
        ;;
      'unicorn')
        start_unicorn
        ;;
      'dj')
        start_delayedjob
        ;;
    esac
    ;;
  'stop')
    case $2 in
      'all')
        stop_unicorn
        stop_delayedjob
        stop_nginx
        stop_memcached
        ;;
      'web')
        stop_unicorn
        stop_nginx
        stop_memcached
        ;;
      'unicorn')
        stop_unicorn
        ;;
      'dj')
        stop_delayedjob
        ;;
    esac
    ;;
  'status')
    case $2 in
      'all')
        status_unicorn
        status_delayedjob
        status_nginx
        status_memcached
        ;;
      'web')
        status_unicorn
        status_nginx
        status_memcached
        ;;
      'unicorn')
        status_unicorn
        ;;
      'dj')
        status_delayedjob
        ;;
    esac
    ;;
  'restart')
    case $2 in
      'all')
        restart_unicorn
        restart_delayedjob
        restart_nginx
        restart_memcached
        ;;
      'web')
        restart_unicorn
        restart_nginx
        restart_memcached
        ;;
      'unicorn')
        restart_unicorn
        ;;
      'dj')
        restart_delayedjob
        ;;
    esac
    ;;
esac
