# check-vpn-speeds

This a simple script that I run from within my "/etc/openvpn" folder to test all of the available conf connection files. To use this simple script, make sure all of your conf files have the line:

auth-user-pass /etc/openvpn/login

This line usually has only "auth-user-pass" without the included "login" file. This means you will also need to create the "login" file with the first line being your VPN provider's user name, and the second line being the VPN provider's password. Chmod that fill to 600 so that only the root user can access it.

This script also relies on the "speedtest-cli" script being present within the "/etc/openvpn" folder as well, as that is what is used to conduct the speed tests for each of the VPN connections. You can clone that repository at the following URL:

https://github.com/sivel/speedtest-cli

You do not need the entire repository. Look in the readme of that repo for the exact git clone command to clone only the speedtest-cli file.
