#!/bin/bash
# Version 0.962 (logstash)
direction=upstream
target="$(curl -s project-mayhem.se/probes/ip.txt)"
count=$(( ( RANDOM % 9999 )  + 100 ))

### WiFi stuff
phy=vht # What PHY?
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':')
iwdetect="$(ifconfig | egrep wl | wc -l)"
# iw $iwnic link | egrep 'bitrate|signal' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | xargs | sed -e "s/^/$direction /" | awk '{print $1,$3,$7,$10,$11,$12,$13}' | tr -d 'MHz' # VHT template
# iw $iwnic link | egrep 'flags|bitrate|signal' | xargs | sed -e "s/^/$direction /" | awk '{print $1,$3,$7,$10,$11,$12}' | tr -d MHz # HT template

#logevent='"$(logger -p info)"'

# Uncomment to use Iperf TCP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s  && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction" | logger -p info
    /bin/iperf3 --client $target -T $direction -P 15 -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] tcp daemon started" | logger -p info & if [ $iwdetect -gt 0 ]; then
    iw $iwnic station dump | egrep 'rx bitrate|signal' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e "s/^/$direction /" | awk '{print $1,$3,$15,$18,$19,$20}' | tr -d 'MHz' | logger -t tx_linkstats_$phy[$(echo $count)] -p local3.debug && iw $iwnic station dump | egrep 'rx bitrate|signal' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e "s/^/$direction /" | awk '{print $1,$3,$15,$18,$19,$20}' | tr -d 'MHz' | logger -t rx_linkstats_$phy[$(echo $count)] -p local3.debug && iw $iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[$(echo $count)] -p local3.debug
 else echo 'No WiFi NIC detected'>/dev/stdout;fi
        sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template $direction N:$(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}')    
;;
1)  echo "[chprobe_iperf3] iperf tcp daemon is already running" | logger -p info
    while pgrep -f "iperf3 --client" | wc -w | grep 1; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz a daemon is running' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction" | logger -p info
    /bin/iperf3 --client $target -T $direction -P 15 -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] Okey the daemon seems to be finished - starting our tcp daemon" | logger -p info & if [ $iwdetect -gt 0 ]; then
    iw $iwnic station dump | egrep 'rx bitrate|signal' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e "s/^/$direction /" | awk '{print $1,$3,$15,$18,$19,$20}' | tr -d 'MHz' | logger -t tx_linkstats_$phy[$(echo $count)] -p local3.debug && iw $iwnic station dump | egrep 'rx bitrate|signal' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e "s/^/$direction /" | awk '{print $1,$3,$15,$18,$19,$20}' | tr -d 'MHz' | logger -t rx_linkstats_$phy[$(echo $count)] -p local3.debug && iw $iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[$(echo $count)] -p local3.debug
 else echo 'No WiFi NIC detected'>/dev/stdout;fi
        sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template $direction N:$(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}')
;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
