# check-vpn-speeds

I currently use a Raspberry Pi as a VPN "router" on my home network. I want a device that is always on, and always connected to a VPN, so that I can set certain devices to stay protected online. In using this VPN router, I needed a way to cycle my VPN connections based on which connection file provides the fastest download speeds. I tried a few other scripts, and they were a bit "janky" at best, so I set out on creating my own script to handle switching between my VPN connections.

This script is not an "on-the-fly" switch. I use it in an environment where I test the speeds every morning at 4am. Of course, there's a little different in a speed test at 4am and one at 6pm, however this script gives me a great baseline as to which connection is the fastest without any load on it. You could always set it to run twice a day, maybe once in an off-load time and another during a time where load could be at the highest.

## Setup and use

You can download the script anywhere you'd like to use it from, so long as you edit the variables at the top of the file to point to the right locations. This script also relies on sivel's "speedtest-cli" script, which is [located here](https://github.com/sivel/speedtest-cli). Be sure you link to the speedtest-cli script at the top of this one.

## File changes you need to make

There are a few things to consider and setup before using this script.

1. All of your OpenVPN connection files need to probably end in .conf instead of .ovpn. I haven't thoroughly tested this yet, and it might work with them being .ovpn as long as you change the EXTENSION variable at the top of the file to reflect that.
2. Inside of each connection file, be sure you modify the line `auth-user-pass` to read `auth-user-pass login` and then you need to create a file called `login` with the first line being your user name with your VPN provider, and the second line being your password. Once you have created this file, chmod it to 600 so that only the root user can see inside of it. (`sudo chmod 600 login`)
3. Also make sure the `crl.rsa.2048.pem` and `ca.rsa.2048.crt` lines are preceded with the correct location. So if they are stored in your `/etc/openvpn` folder, be sure to modify the line to read `/etc/openvpn/crl.rsa.2048.pem` and `/etc/openvpn/ca.rsa.2048.crt`.

## Running the script on an interval ##

I set mine up to run every morning at 4am. Although server load at 4am is going to vary drastically from the server load at 2pm, when I run this early in the morning I can at least get a baseline for which server is performing the best at the time, and then connect to it automatically. Running every morning also helps to ensure that the Pi is definitely running every day before anyone gets up and before any devices begin to hit the net.

If you would like to set this up as a cron script so that it runs on an interval, you can do that by issuing the crontab command as sudo:

```
sudo crontab -e
```

Once you are inside of the crontab for the root user you can use the following line:

```
0 4 * * * /etc/openvpn/check-vpn-speeds.sh > /etc/openvpn/check-vpn-speeds.log
```

Be sure you modify your cron job so that the `check-vpn-speeds.sh` location is correct, as well as wherever it is you would like the log to be stored. I can imagine that this script would probably work best as a systemd script, and if I could ever figure out how to get it to run that way, I'll update this README accordingly.
