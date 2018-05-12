#!/bin/bash

#################################################################
# CHANGE STUFF HERE ONLY
#################################################################

# WHERE ARE YOU STORING YOUR OPENVPN CONNECTION FILES
# DEFAULT: /etc/openvpn
DIR="/etc/openvpn"

# WHAT EXTENSION DO YOU USE FOR YOUR CONNECTION FILES
# DEFAULT: .conf
EXT=".conf"

# LOCATION OF THE SPEEDTEST-CLI EXECUTABLE
SCLI="/etc/openvpn"

# SECONDS TO WAIT UNTIL VPN CONNECTIONS TIMEOUT AND MOVE ON
TIMEOUT=10

# BEFORE WE BEGIN TO TEST THE DOWNLOAD SPEED FOR A SERVER WE
# PING THE ADDRESS FIRST. IF THE PING RESPONSE IS GREATER THAN
# THE THRESHOLD DEFINED HERE, WE WILL SKIP THAT URL AND NOT
# TEST IT. THIS PREVENTS US FROM RUNNING SPEED TESTS ON URLS
# THAT ARE GOING TO TAKE FOREVER TO COMPLETE.
PINGTHRESHOLD=100

##################################################################
# DO NOT EDIT BELOW THIS LINE
##################################################################

BESTSPEED=0
BESTSPEEDPROVIDER=""

# STOP OPENVPN, KILLING ANY CURRENT CONNECTION
service_stop() {
	# CHECK TO SEE IF THE OPENVPN PROCESS IS RUNNING, AND IF IT IS, STOP IT, IF NOT, DO NOTHING
        #systemctl stop openvpn

	# CHECK IF THE OPENVPN PROCESS IS RUNNING; IF SO, END IT

        # SLEEP FOR 1 SECOND INDEFINITELY UNTIL THE OPENVPN SERVICE IS STOPPED
        while [ "0" != `sudo ifconfig | grep tun0 | wc -l` ]; do
		systemctl stop openvpn
                sleep 1
        done
}

# STARTS OPENVPN WITH A SPECIFIC CONFIGURATION FILE
service_start() {
        systemctl start openvpn@$1.service

	# THIS SECTION WILL FIRST SET A COUNTER TO 0, AT WHICH POINT THE SCRIPT
	# WILL START TO SLEEP EVERY SECOND UNTIL THE TIMEOUT VALUE ABOVE IS
	# HIT. ONCE THAT HAPPENS, WE BREAK OUT OF THE CURRENT FUNCTION AND
	# CONTINUE ON
	COUNTER=0
        while [ "0" == `sudo ifconfig | grep tun0 | wc -l` ]; do
                sleep 1
		COUNTER=$((COUNTER+1))

		# IF OUR COUNTER INCREMENT GOES ABOVE OUT TIMEOUT LIMIT, BREAK OUT
		if [[ $COUNTER -gt $TIMEOUT ]]
		then
			break
		fi
        done
}

# THIS IS WHERE WE CONDUCT THE SPEED TEST, AND SET THE BESTSPEED/BESTSPEEDPROVIDER ACCORDINGLY
speed_test() {
	# BEFORE WE BEGIN TO CONDUCT A SPEED TEST, OR MODIFY OUR BESTSPEED OR BESTSPEEDPROVIDER
	# SETTINGS, WE WANT TO MAKE SURE WE ARE CONNECTED TO THE VPN. OTHERWISE, THE SPEEDTEST
	# WILL BE OUR OWN PROVIDER, AND THE BESTSPEEDPROVIDER WILL BE THE ONE THAT FAILED
	while [ "0" == `sudo ifconfig | grep tun0 | wc -l` ]; do
		echo "VPN CONNECTION FAILED. SKIPPING."
		return 0
        done

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
TOTALFILES=$(ls -1q "$DIR"/*"$EXT" | wc -l)
FILECOUNT=1
for file in "$DIR"/*"$EXT"
do
        file=${file#$DIR/} # REMOVE THE DIRECTORY NAME FROM THE FILE NAME
        file=${file%$EXT} # REMOVE THE EXTENSION FROM THE FILE NAME

        # FIRST, WE SHOULD STOP OPENVPN JUST TO MAKE SURE WE DON'T HAVE AN ACTIVE CONNECTION
        service_stop

	echo "FILE: ${file}$EXT ($FILECOUNT of $TOTALFILES)"

	URLTOTEST=$(awk '/^remote /{print $2}' ${file}$EXT)
	PINGRESPONSEFLOAT=$(ping -c 4 $URLTOTEST | tail -1| awk '{print $4}' | cut -d '/' -f 2)
	PINGRESPONSE=${PINGRESPONSEFLOAT%.*}

	if [[ $PINGRESPONSE -lt $PINGTHRESHOLD ]]
	then
	        # START THE SERVICE
	        service_start ${file}

	        # CONDUCT THE SPEED TEST
	        speed_test ${file}

	        # STOP THE SERVICE SO THAT WE CAN MOVE ON
	        service_stop

	        echo ""
	else
		echo "PING RESPONSE TOO HIGH ($PINGRESPONSEFLOAT). SKIPPING."
		echo ""
	fi
	FILECOUNT=$((FILECOUNT+1))
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
