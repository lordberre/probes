#!/bin/bash

# Vars
masterurl="http://project-mayhem.se/probes"
managerurl="http://project-mayhem.se/files/probemanager"
# Sub-optimal way of determining "default" interface when there is no default route up.. But it should work in most probes.
default_if=`ip link show | awk '{print $2}' | egrep 'en|eth' | head -1 | tr -d ':'`
ENVFILE="/var/chprobe/chprobe_forcedown"
connectivity=true
chprobe_reboot=disable
tinkerboard=false

# Load config file
probe="`cut -d "." -f 2 <<< $(hostname)`"
source /var/chprobe/chprobe.cfg || probedir="/home/chprobe"
source $ENVFILE

# Detect tinkerboards
if [ `uname -r | grep -c rockchip` ];then 
    tinkerboard=true
fi

# Use a different logtag for link events
if [[ $1 = "dispatcher" ]]; then error_tag="chprobe_link_error"
else error_tag="chprobe_network_error"
fi

# Special tinkerboard WA
tinker_ifconfig_wa() {
if [ `grep $default_if /etc/network/interfaces -c` -eq 0 ] && [ $tinkerboard = true ]; then
    ifconfig $default_if up && echo "[$error_tag] Manually set $default_if up with ifconfig since if-scripts arent properly set up"
fi
}

# Restart NM function
restart_nm () {
systemctl restart NetworkManager && echo "[$error_tag] Seems we don't have internet connectivity, restarting NetworkManager in case it's just us" | logger -p local5.err
}

# ProbeReboot function
declare -i probe_uptime=$(printf "%.0f\n" `awk {'print $1'} /proc/uptime`)
reboot_probe () {
echo "[$error_tag] Rebooting probe due to excessive network errors.." | logger -p local5.emerg
reboot
}

set_state() {
noconnectivity="$(ping -c 10 8.8.8.8 | grep 100% | wc -l)"
if [ $noconnectivity -ge 1 ]; then connectivity=false; echo "[$error_tag] Got no errors, but not a single packet went through" | logger -p local5.err
else ping -q -c 1 8.8.8.8
        if [ $? -ge 2 ]; then connectivity=false; echo "[$error_tag] We don't have connectivity (error returned: $?)" | logger -p local5.err 
        fi
fi
}

connectivity_check () {
# Check connectivity and try to recover if not

if [ $noloop -eq 0 ]; then
    set_state
    if    [ $connectivity = false ]; then
         restart_nm
    fi

else
    set_state
    if [ $chprobe_forcedown = false ] && [ $connectivity = false ]; then
        tinker_ifconfig_wa &> /dev/null
        ifdown $default_if
        sleep 5
        ifup $default_if
        echo "[$error_tag] Forced $default_if down and up again.." | logger -p local5.err && echo "chprobe_forcedown=false" > $ENVFILE
    fi
fi
return 
}

# Check journal for entries before checking connectivity
noloop="$(journalctl -S -1h -p 3 --no-pager | grep -c 'restarting NetworkManager')"
connectivity_check

# If script is called by dispatcher, be more aggressive
# connectivity_check will be called again, we'll have the connection status(connectivity var) from the first run
if [[ $1 = "dispatcher" ]]; then connectivity_check && sleep 5
	if [ $connectivity = false ];then
	noloop=1 && connectivity_check
	fi
else
    if [ $connectivity = false ];then
        sleep 5
        connectivity_check
    fi
fi

# Report if connectivity is OK and reset ifup/down variable
if [ $connectivity = true ]; then echo "[chprobe] We have connectivity" | logger -p notice && echo "chprobe_forcedown=false" > $ENVFILE
fi

# Check DNS querys explicitly
dig @8.8.8.8 +time=5 &> /dev/null
if [ $? -eq 0 ]; then echo "[chprobe] DNS responses are OK" | logger -p notice && dns_check=true
else echo "[chprobe] Warning! DNS is not working properly." | logger -p local5.err && dns_check=false
fi

# Logrotate and restart rsyslogd sometimes
declare -i random_number=$(( ( RANDOM % 20 )  + 1 ))
if [ $random_number -eq 10 ]; then
logrotate /etc/logrotate.d/chprobe && systemctl restart rsyslog
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

# Check criterias for rebooting if configured
# Re-evaluate the state since it might've started working again after the most recent if-event

if [ $connectivity = false ] && [ $chprobe_reboot = enable ] && [ $probe_uptime -ge 2000 ]; then
    set_state
    if [ $connectivity = false ]; then
        declare -i reboot_condition=`journalctl -S -2h -p 3 --no-pager | grep -c 'chprobe_network_error'`
        if [ -z ${callhome_interval+x} ]; then
            if [ $reboot_condition -ge 24 ];then
                 reboot_probe
        fi
        else
            interval_formula=`expr 90 \* 120 / 100 / $callhome_interval \* 4`
            if [ $reboot_condition -ge $interval_formula ]; then
                reboot_probe
            fi
        fi
    fi
fi
