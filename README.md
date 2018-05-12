# check-vpn-speeds

## Setup and use

This a simple script that I run from within my `/etc/openvpn` folder to test all of the available conf connection files. To use this simple script, make sure all of your conf files have the line:

```
auth-user-pass /etc/openvpn/login
```

This line usually has only `auth-user-pass` without the included `login` file. This means you will also need to create the `login` file with the first line being your VPN provider's user name, and the second line being the VPN provider's password. Chmod that file to 600 so that only the root user can access it.

This script also relies on the `speedtest-cli` script being present within the `/etc/openvpn` folder as well, as that is what is used to conduct the speed tests for each of the VPN connections. The original git repository is [located here](https://github.com/sivel/speedtest-cli). To use this repo, issue the following terminal commands:

```
wget -O speedtest-cli https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py
chmod +x speedtest-cli
```

## Running the script on an interval ##

I set mine up to run every morning at 4:00am. Although server load at 4:00am is going to vary drastically from the server load at 2:00pm, when I run this early in the morning I can at least get a baseline for which server is performing the best at the time, and then connect to it automatically. Running every morning also helps to ensure that the Pi is definitely running every day before anyone gets up and before any devices begin to hit the net.

If you would like to set this up as a cron script so that it runs on an interval, you can do that by issuing the crontab command as sudo:

```
sudo crontab -e
```

Once you are inside of the crontab for the root user you can use the following line:

```
0 4 * * * /etc/openvpn/check-vpn-speeds.sh > /etc/openvpn/check-vpn-speeds.log
```

I can imagine that this script would probably work best as a systemd script, and if I could ever figure out how to get it to run that way, I'll update this README accordingly.
