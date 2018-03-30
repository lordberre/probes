#!/bin/bash

# Vars
masterurl="http://project-mayhem.se/probes"
managerurl="http://project-mayhem.se/files/probemanager"
# Sub-optimal way of determining "default" interface when there is no default route up.. But it should work in most probes.
default_if=`ip link show | awk '{print $2}' | egrep 'en|eth' | head -1 | tr -d ':'`
ENVFILE="/var/chprobe/chprobe_forcedown"
connectivity=true

# Load config file
probe="`cut -d "." -f 2 <<< $(hostname)`"
source /var/chprobe/${probe}.cfg || probedir="/home/chprobe"
source $ENVFILE

# Restart NM function
restart_nm () {
systemctl restart NetworkManager && echo "[chprobe_error] Seems we don't have internet connectivity, restarting NetworkManager in case it's just us" | logger -p local5.err
}

connectivity_check () {
# Check connectivity and try to recover if not
noconnectivity="$(ping -c 10 8.8.8.8 | grep 100% | wc -l)"

if [ $noloop -eq 0 ]; then
	if [ $noconnectivity -ge 1 ]; then connectivity=false; echo "[chprobe_error] Got no errors, but not a single packet went through" | logger -p local5.err && restart_nm
	else ping -q -c 1 8.8.8.8
		if [ $? -ge 2 ]; then connectivity=false; echo "[chprobe_error] We don't have connectivity (error returned: $?)" | logger -p local5.err && restart_nm
		fi
	fi
else 
	if [ $chprobe_forcedown = false ] && [ $connectivity = false ]; then
ifdown $default_if;sleep 5;ifup $default_if;echo "[chprobe_error] Forced $default_if down and up again.." | logger -p local5.err && echo "chprobe_forcedown=false" > $ENVFILE
	fi
fi
}

# Check journal for entries before reloading NM
noloop="$(tail -n 500 /var/log/messages | grep -c 'Stopping Network Manager')" && connectivity_check

# If script is called by dispatcher, be more aggressive
if [[ $1 = "dispatcher" ]]; then connectivity_check && sleep 5
	if [ $connectivity = false ];then
	noloop=1 && connectivity_check
	fi
else connectivity_check
fi

# Report if connectivity is OK and reset ifup/down variable
if [ $connectivity = true ]; then echo "[chprobe] We have connectivity" | logger -p notice && echo "chprobe_forcedown=false" > $ENVFILE
fi

# Check DNS querys explicitly
dig +time=5 &> /dev/null
if [ $? -eq 0 ]; then echo "[chprobe] DNS responses are OK" | logger -p notice && dns_check=true
else echo "[chprobe] Warning! DNS is not working properly." | logger -p local5.err && dns_check=false
fi

# If enabled, configure SSH Tunnel
if [ $ssh_tunnel = "enable" ]; then

# Check SSH Tunnel status and try to recover. Skip when called by dispatcher since we do it there anyway
   if [ $connectivity = true ] && [[ $1 != "dispatcher" ]]; then
      if [ `systemctl status sshtunnel -l | egrep -c 'error|fail|unreach'` -ge 1 ]; then
      systemctl restart sshtunnel && echo "[chprobe_sshtunnel] Restarted sshtunnel due to errors." | logger -p local5.err
      elif [ `systemctl is-active sshtunnel` != 'active' ]; then
      systemctl restart sshtunnel
      fi
   fi
	if [ $dns_check = "true" ]; then
	curl -m 3 --retry 2 -s -o /var/chprobe/tunnel_ip -XGET $masterurl/${probe}-tunnel_ip.txt
	curl -m 3 --retry 2 -s -o /var/chprobe/tunnel_port -XGET $masterurl/${probe}-tunnel_port.txt
	fi
fi

if [ $dns_check = true ] && [ $connectivity = true ]; then
# Send heartbeats
curl -m 3 -s http://project-mayhem.se --data-ascii DATA -A ${probe} &> /dev/null
curl -L -m 3 --retry 2 -s http://88.198.46.60 | grep Your | awk '{print $4}' | tr -d '</b>' | sed -e "s/^/$(date "+%b %d %H:%M:%S") ${probe} chprobe_wanip[$(echo 9000]): $(cd $probedir && ls version-* | sed 's/\<version\>//g') /" | tr -s ' ' | tr -d '-' >> /var/log/chprobe_wanip.txt

# Update Probemanager
curl -m 3 --retry 2 -s -o ${probedir}probemanager $managerurl &> /dev/null && chmod +x ${probedir}probemanager &> /dev/null
fi
