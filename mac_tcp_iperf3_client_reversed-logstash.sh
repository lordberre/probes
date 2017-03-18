#!/bin/bash
# Version 0.962b (logstash / mac)
direction=downstream
target="$(curl -s project-mayhem.se/probes/ip.txt)"
count=$(( ( RANDOM % 9999 )  + 100 ))

### WiFi stuff
phy=vht # What PHY?
run_airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | egrep 'Rate|MCS|channel|agrCtlRSSI|CtlNoise' | tr -d 'agrCtlRSSI|agrCtlNoise|lastTxRate|maxRate|MCS|channel|:' | tr -d ' ' | sed 's/,/ /g' | xargs"
maclogdir=/Users/testlabbet-pro/Labb-stuff/logz/iperf3tcp.log
maclogformat='sed -e "s/^/$(date "+%b %d %H:%M:%S") $(hostname) tx_airport_linkstats_$phy[$(echo $count)]: /"'
maclogformat2='sed -e "s/^/$(date "+%b %d %H:%M:%S") $(hostname) iperf3tcp[$(echo $count)]: /"'
twentymhzformat='sed -e "s/^/$(date "+%b %d %H:%M:%S") $(hostname) tx_airport_linkstats[$(echo $count)]: /"'
linkformat=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep channel | egrep '40|80' | wc -w | tr -d ' ')

#iwnic=$(ifconfig | grep en0 | grep -v inet | awk '{print $1}' | tr -d ':')
#iwdetect="$(ifconfig | egrep en0 | grep -v inet | wc -l)"

# Uncomment to use Iperf TCP Daemon (with random timer)
case $(pgrep -f "iperf3 --client" | wc -w | tr -d ' ') in

0)  echo "[chprobe_iperf3] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s  && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - $direction" | logger -p info
    /usr/local/bin/iperf3 --client $target -T $direction -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | eval $maclogformat2 >>$maclogdir & echo "[chprobe_iperf3] tcp daemon started" | logger -p info
        eval $run_airport | sed -e "s/^/$direction /" | if [ $linkformat -ge 1 ]; then eval $maclogformat;else eval $twentymhzformat;fi >>$maclogdir
    ;;
1)  echo "[chprobe_iperf3] iperf tcp daemon is already running" | logger -p info
	while pgrep -f "iperf3 --client" | wc -w | grep 1; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz a daemon is running' | logger -p info;done
	    echo "[chprobe_iperf3] Starting the tcp daemon - $direction" | logger -p info
	        /usr/local/bin/iperf3 --client $target -T $direction -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | eval $maclogformat2 >>$maclogdir & echo "[chprobe_iperf3] tcp daemon started" | logger -p info
		        eval $run_airport | sed -e "s/^/$direction /" | if [ $linkformat -ge 1 ]; then eval $maclogformat;else eval $twentymhzformat;fi >>$maclogdir
		;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
