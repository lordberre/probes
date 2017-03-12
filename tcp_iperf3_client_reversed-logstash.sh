#!/bin/bash
# Version 0.961 (logstash)
direction=downstream
target="$(curl -s project-mayhem.se/probes/ip.txt)"
count=$(( ( RANDOM % 9999 )  + 100 ))

### WiFi stuff
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':')
iwdetect="$(ifconfig | egrep wl | wc -l)"
# iw $iwnic link | egrep 'bitrate|signal' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | xargs | sed -e "s/^/$direction /" | awk '{print $1,$3,$7,$10,$11,$12,$13}' | tr -d 'MHz' | sed 's/$/vht/'
# iw $iwnic link | egrep 'flags|bitrate|signal' | xargs | sed -e "s/^/$direction /" | awk '{print $1,$3,$7,$10,$11,$12}' | tr -d MHz # HT template
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf TCP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s  && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction" | logger -p info
    /bin/iperf3 --client $target -T $direction -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] tcp daemon started" | logger -p info & if [ $iwdetect -ge 0 ]; then
    iw $iwnic link | egrep 'bitrate|signal' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | xargs | sed -e "s/^/$direction /" | awk '{print $1,$3,$7,$10,$11,$12,$13}' | tr -d 'MHz' | sed 's/$/vht/' | logger -t linkstats[$(echo $count)] -p local3.debug
 else 'No WiFi NIC detected';fi
    ;;
1)  echo "[chprobe_iperf3] iperf tcp daemon is already running" | logger -p info
    while pgrep -f "iperf3 --client" | wc -w | grep 1; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz a daemon is running' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction"
    /bin/iperf3 --client $target -T $direction -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] Okey the daemon seems to be finished - starting our tcp daemon" | logger -p info & if [ $iwdetect -ge 0 ]; then
    iw $iwnic link | egrep 'bitrate|signal' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | xargs | sed -e "s/^/$direction /" | awk '{print $1,$3,$7,$10,$11,$12,$13}' | tr -d 'MHz' | sed 's/$/vht/' | logger -t linkstats[$(echo $count)] -p local3.debug
 else 'No WiFi NIC detected';fi
    ;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
