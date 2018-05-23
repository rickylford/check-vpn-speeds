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

# LOG FILE LOCATION WITH FULL PATH
LOGLOCATION="/var/log/check-vpn-speeds.log"

# INTERFACE FOR VPN CONNECTIONS
VPNINTERFACE="tun0"

# ETHERNET INTERFACE
ETHERNETINTERFACE="enp4s0"

# DO YOU WANT TO AUTOMATICALLY CONFIGURE YOUR FIREWALL?
# WARNING: THIS WILL DELETE AND OVERWRITE ANY CURRENT
# FIREWALL RULES YOU MAY HAVE IN PLACE
CONFIGFIREWALL=true

##################################################################
# DO NOT EDIT BELOW THIS LINE
##################################################################

# -------------------------------------------------- #
# MAKE SURE EVERYTHING WE NEED EXISTS OR IS INTALLED #
# -------------------------------------------------- #

ETHERNETEXISTS=$(ifconfig | grep $ETHERNETINTERFACE)

if [ ! -f $SCLI/speedtest-cli ]; then
	echo "ERROR: speedtest-cli does not exist. Exiting."
	exit 1
elif [ ! -f /usr/sbin/netfilter-persistent ]; then
	if [ "$CONFIGFIREWALL" = true ]; then
		echo "ERROR: netfilter-persistent not installed. Exiting."
		exit 1
	fi
elif [ -z "$ETHERNETEXISTS" ]; then
	echo "ERROR: $ETHERNETINTERFACE does not exist. Exiting."
	exit 1
fi

# ---------------------------- #
# PROCEED WITH EVERYTHING ELSE #
# ---------------------------- #

BESTSPEED=0
BESTSPEEDPROVIDER=""

# RESET ALL UFW RULES TO START FROM SCRATCH
firewall_reset() {
	if [ "$CONFIGFIREWALL" = true ]; then
		iptables -P FORWARD ACCEPT > /dev/null 2>&1
		iptables -P OUTPUT ACCEPT > /dev/null 2>&1
		iptables -t nat -F > /dev/null 2>&1
		iptables -t mangle -F > /dev/null 2>&1
		iptables -F > /dev/null 2>&1
		iptables -X > /dev/null 2>&1
		netfilter-persistent save > /dev/null 2>&1
	fi
}

# SET AND ENABLE ALL OF THE APPROPRIATE UFW RULES
firewall_on() {
	if [ "$CONFIGFIREWALL" = true ]; then
		firewall_reset

		iptables -t nat -A POSTROUTING -o $VPNINTERFACE -j MASQUERADE > /dev/null 2>&1
		iptables -A FORWARD -i enp4s0 -o $VPNINTERFACE -j ACCEPT > /dev/null 2>&1
		iptables -A FORWARD -i tun0 -o $ETHERNETINTERFACE -j ACCEPT > /dev/null 2>&1
		iptables -P FORWARD DROP > /dev/null 2>&1

		netfilter-persistent save > /dev/null 2>&1
	fi
}

# STOP OPENVPN, KILLING ANY CURRENT CONNECTION
# ALSO, RESET UFW TO ALLOW OUTBOUND CONNECTIONS
service_stop() {
	echo "[ $(date) ]: service_stop() FUNCTION STARTED" >> $LOGLOCATION

        # SLEEP FOR 1 SECOND INDEFINITELY UNTIL THE OPENVPN SERVICE IS STOPPED
        while [ "0" != `sudo ifconfig | grep $VPNINTERFACE | wc -l` ]; do
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
        while [ "0" == `sudo ifconfig | grep $VPNINTERFACE | wc -l` ]; do
                sleep 1
		COUNTER=$((COUNTER+1))

		# IF OUR COUNTER INCREMENT GOES ABOVE OUR TIMEOUT LIMIT, BREAK OUT
		if [[ $COUNTER -ge $TIMEOUT ]]
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
	while [ "0" == `sudo ifconfig | grep $VPNINTERFACE | wc -l` ]; do
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

# BEFORE WE DO ANYTHING, LET'S TURN OUR FIREWALL OFF SO THAT WE CAN BEGIN TESTING
if [ "$CONFIGFIREWALL" = true ]; then
	firewall_reset
fi

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
		echo "[ $(date) ]: SETTING UFW RULES" >> $LOGLOCATION

                echo "CONNECTING TO: $BESTSPEEDPROVIDER"
                systemctl start openvpn@$BESTSPEEDPROVIDER.service

		# WE NEED TO WAIT UNTIL THE VPN INTERFACE COMES UP, THEN WE WILL
		# SET OUR FIREWALL RULES APPROPRIATELY USING THE IP ADDRESS OF OUR TUNNEL
		while [ "0" == `sudo ifconfig | grep $VPNINTERFACE | wc -l` ]; do
			sleep 1
		done

		# GET THE VPN INTERFACE IP ADDRESS
		TUNIP=$(ip addr show $VPNINTERFACE | grep -Po 'inet \K[\d.]+')
		TUNPORT=$(awk '/^remote /{print $3}' $DIR/$BESTSPEEDPROVIDER$EXT)

		echo "[ $(date) ]: VPN IP ADDRESS IS $TUNIP" >> $LOGLOCATION

		# NOW LET'S TURN THE FIREWALL ON
		echo "[ $(date) ]: STARTING THE FIREWALL (IF THAT HAS BEEN ALLOWED)" >> $LOGLOCATION
		firewall_on $TUNIP $TUNPORT
        fi
fi
