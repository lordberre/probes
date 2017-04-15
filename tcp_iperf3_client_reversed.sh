#!/bin/bash
# Version 0.965
direction=downstream
logfacility=local3.debug
target="$(curl -s project-mayhem.se/probes/ip.txt)"
count=$(( ( RANDOM % 9999 )  + 100 ))
# rrd_db="rrdtool update /home/chprobe/tcpdb_\$\(hostname -d\).rrd --template \$direction N:\$\(tail /var/log/iperf3tcp.log | egrep \$count | awk '\{print \$7\}'\)"

### WiFi stuff
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':') # Is there a wireless interface?
iwdetect="$(grep up /sys/class/net/wl*/operstate | wc -l)" # Detect wireless interface state
wififreq="$(iw $iwnic link | grep freq | awk '{print $2}')" # Detect frequency (2.4GHz or 5Ghz)
phydetect="$(iw $iwnic link | grep VHT | wc -l)" # What PHY? (Legacy is not supported)
#phy=$1 # Use argument for PHY instead

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

# Iperf daemon settings and conditions
	while [ `pgrep -f 'bbk_cli|wrk' | wc -w` -ge 1 ];do sleep 0.5
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s  && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction" | logger -p info
    /bin/iperf3 --client $target -T $direction -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p $logfacility & echo "[chprobe_iperf3] tcp daemon started" | logger -p info & 
    if [ $iwdetect -gt 0 ]; then
	    if [ $wififreq -lt 2500 ]; then phy=ht & eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht & eval $vhtparse;else phy=ht eval $htparse;fi;fi	    
	    else echo 'No WiFi NIC detected'>/dev/stdout;fi        
sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template $direction N:$(tail /var/log/iperf3tcp.log | egrep $count | grep iperf3 | awk '{print $7}')
	;;
1)  echo "[chprobe_iperf3] iperf tcp daemon is already running" | logger -p info
          while [ `pgrep -f 'iperf3 --client|bbk_cli|wrk' | wc -w` -ge 1 ]; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz either an iperf3 or a bbk daemon is running' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction"
    /bin/iperf3 --client $target -T $direction -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p $logfacility & echo "[chprobe_iperf3] Okey the daemon seems to be finished - starting our tcp daemon" | logger -p info &
       if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht & eval $htparse;else
                    if [ $phydetect -ge 1 ]; then phy=vht & eval $vhtparse;else phy=ht eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi 
	sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template $direction N:$(tail /var/log/iperf3tcp.log | egrep $count | grep iperf3 | awk '{print $7}')
   ;;
*)  echo "[chprobe_iperf3] multiple instances of iperf3 daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
