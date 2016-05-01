#!/bin/bash

SED=`which sed`;
GREP=`which grep`;
DEFAULT_HTTPD_CONFIG="${OPENSHIFT_PYTHON_DIR}/versions/2.2/etc/conf/httpd.conf";
TOTALMEM=`free -m | grep Mem | awk '{print $2}'`;
MAX_CLIENTS=$(($TOTALMEM / 40));
START_SERVERS=$(($TOTALMEM / 50));

backupConfig() {
    cp $1 $1.autobackup
}


applyOptimizations(){
        backupConfig $DEFAULT_HTTPD_CONFIG;
        $SED -i "/ServerLimit/c\ServerLimit     $MAX_CLIENTS" $DEFAULT_HTTPD_CONFIG;
        $SED -i "/MaxClients/c\MaxClients     $MAX_CLIENTS" $DEFAULT_HTTPD_CONFIG;
        $SED -i "/StartServers/c\StartServers     $START_SERVERS" $DEFAULT_HTTPD_CONFIG;
}

applyOptimizations
