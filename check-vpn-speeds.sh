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
SCLI="/data/Scripts"

# SECONDS TO WAIT UNTIL VPN CONNECTIONS TIMEOUT AND MOVE ON
TIMEOUT=10

# BEFORE WE BEGIN TO TEST THE DOWNLOAD SPEED FOR A SERVER WE
# PING THE ADDRESS FIRST. IF THE PING RESPONSE IS GREATER THAN
# THE THRESHOLD DEFINED HERE, WE WILL SKIP THAT URL AND NOT
# TEST IT. THIS PREVENTS US FROM RUNNING SPEED TESTS ON URLS
# THAT ARE GOING TO TAKE FOREVER TO COMPLETE.
PINGTHRESHOLD=100

# LOG FILE LOCATION WITH FULL PATH
LOGLOCATION="/var/log/check-vpn-speeds.log"

##################################################################
# DO NOT EDIT BELOW THIS LINE
##################################################################

BESTSPEED=0
BESTSPEEDPROVIDER=""

# STOP OPENVPN, KILLING ANY CURRENT CONNECTION
service_stop() {
	echo "[ $(date) ]: service_stop() FUNCTION STARTED" >> $LOGLOCATION

        # SLEEP FOR 1 SECOND INDEFINITELY UNTIL THE OPENVPN SERVICE IS STOPPED
        while [ "0" != `sudo ifconfig | grep tun0 | wc -l` ]; do
		echo "[ $(date) ]: STOPPING OPENVPN SYSTEMCTL" >> $LOGLOCATION
		systemctl stop openvpn
                sleep 1
        done

	echo "[ $(date) ]: service_stop() FUNCTION COMPLETED" >> $LOGLOCATION
}

# STARTS OPENVPN WITH A SPECIFIC CONFIGURATION FILE
service_start() {
	echo "[ $(date) ]: service_start() FUNCTION STARTED" >> $LOGLOCATION

	echo "[ $(date) ]: STARTING OPENVPN SERVICE WITH $1" >> $LOGLOCATION
        systemctl start openvpn@$1.service

	# THIS SECTION WILL FIRST SET A COUNTER TO 0, AT WHICH POINT THE SCRIPT
	# WILL START TO SLEEP EVERY SECOND UNTIL THE TIMEOUT VALUE ABOVE IS
	# HIT. ONCE THAT HAPPENS, WE BREAK OUT OF THE CURRENT FUNCTION AND
	# CONTINUE ON
	COUNTER=0
        while [ "0" == `sudo ifconfig | grep tun0 | wc -l` ]; do
                sleep 1
		COUNTER=$((COUNTER+1))

		# IF OUR COUNTER INCREMENT GOES ABOVE OUR TIMEOUT LIMIT, BREAK OUT
		if [[ $COUNTER -gt $TIMEOUT ]]
		then
			echo "[ $(date) ]: service_start() COUNTER MAXED OUT; BREAKING FROM FUNCTION" >> $LOGLOCATION
			break
		fi
        done

	echo "[ $(date) ]: service_start() FUNCTION COMPLETED" >> $LOGLOCATION
}

# THIS IS WHERE WE CONDUCT THE SPEED TEST, AND SET THE BESTSPEED/BESTSPEEDPROVIDER ACCORDINGLY
speed_test() {
	# BEFORE WE BEGIN TO CONDUCT A SPEED TEST, OR MODIFY OUR BESTSPEED OR BESTSPEEDPROVIDER
	# SETTINGS, WE WANT TO MAKE SURE WE ARE CONNECTED TO THE VPN. OTHERWISE, THE SPEEDTEST
	# WILL BE OUR OWN PROVIDER, AND THE BESTSPEEDPROVIDER WILL BE THE ONE THAT FAILED
	while [ "0" == `sudo ifconfig | grep tun0 | wc -l` ]; do
		echo "[ $(date) ]: CONNECTION TO $1 VPN FAILED. SKIPPING IT." >> $LOGLOCATION

		echo "VPN CONNECTION FAILED. SKIPPING."
		return 0
        done

        IPCITY=$(curl -s ipinfo.io/city)
        IPADDRESS=$(curl -s ipinfo.io/ip)

        echo "INFO: $IPCITY / $IPADDRESS"
	echo "[ $(date) ]: $1 INFO: $IPCITY / $IPADDRESS" >> $LOGLOCATION

        TESTRESULT=$($SCLI/speedtest-cli --no-upload --no-pre-allocate | grep Download | cut -d ' ' -f 2 | cut -d '.' -f 1)

        echo "DOWNLOAD: $TESTRESULT MB/s"
	echo "[ $(date) ]: $1 SPEEDTEST RESULT: $TESTRESULT MB/s" >> $LOGLOCATION

        if [[ $TESTRESULT -gt $BESTSPEED ]]
        then
		echo "[ $(date) ]: $1 DETECTED AS BEST RESULT SO FAR" >> $LOGLOCATION
                BESTSPEED=$TESTRESULT
                BESTSPEEDPROVIDER=$1
        fi
}

# RUN THROUGH THE LIST OF VPN CONNECTION FILES IN THE OPENVPN DIRECTORY
TOTALFILES=$(ls -1q "$DIR"/*"$EXT" | wc -l)
echo "[ $(date) ]: FOUND $TOTALFILES $EXT FILES IN $DIR" >> $LOGLOCATION

FILECOUNT=1
for file in "$DIR"/*"$EXT"
do
        file=${file#$DIR/} # REMOVE THE DIRECTORY NAME FROM THE FILE NAME
        file=${file%$EXT} # REMOVE THE EXTENSION FROM THE FILE NAME

        # FIRST, WE SHOULD STOP OPENVPN JUST TO MAKE SURE WE DON'T HAVE AN ACTIVE CONNECTION
	echo "[ $(date) ]: CALLING SERVICE_STOP FUNCTION" >> $LOGLOCATION
        service_stop

	echo "FILE: ${file}$EXT ($FILECOUNT of $TOTALFILES)"

	URLTOTEST=$(awk '/^remote /{print $2}' $DIR/${file}$EXT)
	PINGRESPONSEFLOAT=$(ping -c 4 $URLTOTEST | tail -1| awk '{print $4}' | cut -d '/' -f 2)
	PINGRESPONSE=${PINGRESPONSEFLOAT%.*}
	echo "[ $(date) ]: GETTING $PINGRESPONSEFLOAT AVERAGE PING TO $URLTOTEST" >> $LOGLOCATION

	if [[ $PINGRESPONSE -lt $PINGTHRESHOLD ]]
	then
		echo "[ $(date) ]: PING RESPONSE IS WITHIN THRESHOLD" >> $LOGLOCATION

	        # START THE SERVICE
		echo "[ $(date) ]: FUNCTION CALL : service_start ${file}" >> $LOGLOCATION
	        service_start ${file}

	        # CONDUCT THE SPEED TEST
		echo "[ $(date) ]: FUNCTION CALL : speed_test ${file}" >> $LOGLOCATION
	        speed_test ${file}

	        # STOP THE SERVICE SO THAT WE CAN MOVE ON
		echo "[ $(date) ]: FUNCTION CALL : service_stop" >> $LOGLOCATION
	        service_stop

	        echo ""
	else
		echo "[ $(date) ]: PING RESPONSE WAS TOO HIGH; SKIPPING THIS $EXT FILE." >> $LOGLOCATION

		echo "PING RESPONSE TOO HIGH ($PINGRESPONSEFLOAT). SKIPPING."
		echo ""
	fi

	FILECOUNT=$((FILECOUNT+1))
done

# IF WE CAPTURED A BEST SPEED AT ONE POINT, LET'S CONTINUE TO THE NEXT CHECK
if [[ $BESTSPEED -gt 0 ]]
then
	echo "[ $(date) ]: WE HAVE A HIGH SPEED BETTER THAN 0" >> $LOGLOCATION

        # SINCE WE HAVE A BEST SPEED, DO WE HAVE AN ACTUAL PROVIDER?
        if [ $BESTSPEEDPROVIDER != "" ]
        then
		echo "[ $(date) ]: SETTING VPN CONNECTION TO $BESTSPEEDPROVIDER" >> $LOGLOCATION

                echo "CONNECTING TO: $BESTSPEEDPROVIDER"
                systemctl start openvpn@$BESTSPEEDPROVIDER.service
        fi
fi
