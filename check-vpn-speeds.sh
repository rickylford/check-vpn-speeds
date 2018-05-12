#!/bin/bash

dir="/etc/openvpn/"
ext=".conf"

service_stop() {
        systemctl stop openvpn
        sleep 5
}

service_start() {
        echo "-------------------------------------------------"
        echo "CONNECTION: openvpn@$1"
        systemctl start openvpn@$1.service
        sleep 5
}

speed_test() {
        ipcity=$(curl -s ipinfo.io/city)
        ipaddress=$(curl -s ipinfo.io/ip)
        echo "IP INFO: $ipcity / $ipaddress"
        ./speedtest-cli --no-upload --no-pre-allocate | grep Download
}

for file in "$dir"*"$ext"
do
        file=${file#$dir}
        file=${file%$ext}

        service_start ${file}
        speed_test
        service_stop
done

echo "-------------------------------------------------"
