#!/bin/bash

#
# Start up script to for job fetcher
#

# Get the script's path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LOG="${DIR}/log/fetcher.log"
ENVIRONMENT="production"
PROJECT_NAME="cloudwick-sync"
VERSION="1.0"
ASSEMBLY_JAR="${DIR}/target/scala-2.10/${PROJECT_NAME}-assembly-${VERSION}.jar"

function usage () {
  echo "Usage: `basename $0` [dice|indeed] [daily|weekly|hourly] [hadoop|spark|cassandra]"
  exit 1
}

if [[ $# -ne 3 ]]; then
  usage
fi

if [[ ! -f $ASSEMBLY_JAR ]]; then
  echo "[ERROR]: Cannot find jar, generate using 'sbt assembly'"
  echo "  This requires installing 'sbt'(version 0.13.6+)"
  exit 1
fi

JAVA=java
if [[ -n "$JAVA_HOME" ]]; then
  JAVA="${JAVA_HOME}/bin/java"
fi
JAVA_HEAP_SIZE=-Xmx1024m

SOURCE=$1

if [[ "$SOURCE" == "dice" ]]; then
  CLASS="com.cloudwick.sync.jobs.fetcher.Start"
elif [[ "$SOURCE" == "indeed" ]]; then
  CLASS="com.cloudwick.sync.jobs.fetcher.Start"
else
  usage
fi

echo "Working DIR: ${DIR}"
echo "Logging to: ${LOG}"
echo "JAR: ${ASSEMBLY_JAR}"
echo "CLASS: ${CLASS}"
echo "Arguments: $@"

set -x
exec "$JAVA" $java_args -cp $ASSEMBLY_JAR $CLASS "$@"
