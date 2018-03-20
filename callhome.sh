#!/bin/bash

# Vars
masterurl="http://project-mayhem.se/probes"
probe=$(hostname -d)
# Sub-optimal way of determining "default" interface when there is no default route up.. But it should work in most probes.
default_ifs=`ip link show | awk '{print $2}' | egrep 'en|eth' | head -1 | tr -d ':'`
ENVFILE="/var/chprobe/chprobe_forcedown"

# Load config file
source /var/chprobe/$(hostname -d).cfg
source $ENVFILE

# Check connectivity and try to recover if not
noconnectivity="$(ping -c 10 8.8.8.8 | grep 100% | wc -l)"
noloop="$(tail -n 500 /var/log/messages | grep 'Stopping Network Manager' | wc -l)"
if [ $noconnectivity -ge 1 ]; then echo "[chprobe_error] Got no errors, but not a single packet went through" | logger -p local5.err
       if [ $noloop -ge 1 ];then echo "[chprobe_error] We've already restarted Network Manager recently, no point in doing it again." | logger -p local5.err
       else systemctl restart NetworkManager && echo "[chprobe_error] Seems we don't have internet connectivity, restarting NetworkManager in case it's just us" | logger -p local5.err;fi
       else 

# In case ping returns errors
ping -q -c 1 8.8.8.8
if [ $? -ge 2 ]; then echo "[chprobe_error] We don't have connectivity (error returned: $?)" | logger -p local5.err && noconnectivity=1
	if [ $noloop -ge 1 ];then echo "[chprobe_error] We've already restarted Network Manager recently, no point in doing it again." | logger -p local5.err
	   if [ $chprobe_forcedown = false ]; then
	ifdown $default_if;sleep 1;ifup $default_if;echo "[chprobe_error] Forced $default_if down and up again.." && echo "chprobe_forcedown=true" > $ENVFILE
	   fi
        else systemctl restart NetworkManager && echo "[chprobe_error] Seems we don't have internet connectivity, restarting NetworkManager in case it's just us" | logger -p local5.err && noconnectivity=1;fi
else
	echo "[chprobe] We have connectivity" | logger -p notice && connectivity=true && echo "chprobe_forcedown=false" > $ENVFILE
	fi
fi

# Say hello to backend server
probedir=/home/chprobe
curl -m 3 -s http://project-mayhem.se --data-ascii DATA -A $(hostname -d) &> /dev/null
curl -L -m 3 --retry 2 -s http://88.198.46.60 | grep Your | awk '{print $4}' | tr -d '</b>' | sed -e "s/^/$(date "+%b %d %H:%M:%S") $(hostname -d) chprobe_wanip[$(echo 9000]): $(cd $probedir && ls version-* | sed 's/\<version\>//g') /" | tr -s ' ' | tr -d '-' >> /var/log/chprobe_wanip.txt

# If enabled, configure SSH Tunnel
if [ $ssh_tunnel = "enable" ]; then
curl -m 3 --retry 2 -s -o /var/chprobe/tunnel_ip -XGET $masterurl/${probe}-tunnel_ip.txt
curl -m 3 --retry 2 -s -o /var/chprobe/tunnel_port -XGET $masterurl/${probe}-tunnel_port.txt

# Check SSH Tunnel status and try to recover
   if [ $noconnectivity -eq 0 ]; then
      if [ `systemctl status sshtunnel -l | egrep -c 'error|fail|unreach'` -ge 1 ]; then
      systemctl restart sshtunnel && echo "[chprobe_sshtunnel] Restarted sshtunnel due to errors." | logger -p local5.err
      elif [ `systemctl is-active sshtunnel` != 'active' ]; then
      systemctl restart sshtunnel
      fi
   fi
fi
