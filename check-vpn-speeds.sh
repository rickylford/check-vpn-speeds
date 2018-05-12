#!/bin/bash

#################################################################
# CHANGE STUFF HERE ONLY
#################################################################

# WHERE ARE YOU STORING YOUR OPENVPN CONNECTION FILES
# DEFAULT IS /etc/openvpn/ -- WITH THE TRAILING SLASH
DIR="/etc/openvpn/"

# WHAT EXTENSION DO YOU USE FOR YOUR CONNECTION FILES
# DEFAULT IS .conf
EXT=".conf"

# LOCATION OF THE SPEEDTEST-CLI EXECUTABLE
SCLI="/etc/openvpn"

##################################################################
## DO NOT EDIT BELOW THIS LINE
##################################################################

BESTSPEED=0
BESTSPEEDPROVIDER=""

# STOP OPENVPN, KILLING ANY CURRENT CONNECTION
service_stop() {
        systemctl stop openvpn

        # SLEEP FOR 1 SECOND INDEFINITELY UNTIL THE OPENVPN SERVICE IS STOPPED
        while [ "0" != `sudo ifconfig | grep tun0 | wc -l` ]; do
                sleep 1
        done
}

# STARTS OPENVPN WITH A SPECIFIC CONFIGURATION FILE
service_start() {
        echo "FILE: $1$EXT"

        systemctl start openvpn@$1.service

        # SLEEP FOR 1 SECOND INDEFINITELY UNTIL THE VPN SERVICE IS STARTED
        while [ "0" == `sudo ifconfig | grep tun0 | wc -l` ]; do
                sleep 1
        done
}

# THIS IS WHERE WE CONDUCT THE SPEED TEST, AND SET THE BESTSPEED/BESTSPEEDPROVIDER ACCORDINGLY
speed_test() {
        IPCITY=$(curl -s ipinfo.io/city)
        IPADDRESS=$(curl -s ipinfo.io/ip)
        echo "INFO: $IPCITY / $IPADDRESS"

        TESTRESULT=$($SCLI/speedtest-cli --no-upload --no-pre-allocate | grep Download | cut -d ' ' -f 2 | cut -d '.' -f 1)
        echo "DOWNLOAD: $TESTRESULT MB/s"

        if [[ $TESTRESULT -gt $BESTSPEED ]]
        then
                BESTSPEED=$TESTRESULT
                BESTSPEEDPROVIDER=$1
        fi
}

# RUN THROUGH THE LIST OF VPN CONNECTION FILES IN THE OPENVPN DIRECTORY
for file in "$DIR"*"$EXT"
do
        file=${file#$DIR} # REMOVE THE DIRECTORY NAME FROM THE FILE NAME
        file=${file%$EXT} # REMOVE THE EXTENSION FROM THE FILE NAME

        # FIRST, WE SHOULD STOP OPENVPN JUST TO MAKE SURE WE DON'T HAVE AN ACTIVE CONNECTION
        service_stop

        # START THE SERVICE
        service_start ${file}

        # CONDUCT THE SPEED TEST
        speed_test ${file}

        # STOP THE SERVICE SO THAT WE CAN MOVE ON
        service_stop

        echo ""
done

# IF WE CAPTURED A BEST SPEED AT ONE POINT, LET'S CONTINUE TO THE NEXT CHECK
if [[ $BESTSPEED -gt 0 ]]
then
        # SINCE WE HAVE A BEST SPEED, DO WE HAVE AN ACTUAL PROVIDER?
        if [ $BESTSPEEDPROVIDER != "" ]
        then
                echo "CONNECTING TO: $BESTSPEEDPROVIDER"
                systemctl start openvpn@$BESTSPEEDPROVIDER.service
        fi
fi
