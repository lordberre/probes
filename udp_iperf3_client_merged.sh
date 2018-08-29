#!/bin/bash
# Version 1.50.0. Added wifipoller to replace redundant code.

while true
do
        case "$1" in
	-ds) direction="downstream" && break ;;
	-us) direction="upstream" && break ;;
	-h)  cat <<USAGE
usage: $0 [-ds] [-us] [-h]

    -h) See this help
    -us) Upstream UDP test
    -ds) Downstream UDP test
USAGE
            exit 1
            ;;
        *)
            echo Use -h for help!
            exit 1;
            ;;
    esac;done

shift

# Vars
logfacility=local4.debug
logtag=chprobe_iperf3udp
count=$(( ( RANDOM % 9999 )  + 1 ))
probedir="/home/chprobe"

# Default settings
declare -i chprobe_iperf3udp_stream_b1=5
declare -i chprobe_iperf3udp_stream_b2=10
declare -i chprobe_iperf3udp_stream_b3=20
declare -i chprobe_iperf3udp_stream_t1=60
declare -i chprobe_iperf3udp_stream_t2=60
declare -i chprobe_iperf3udp_stream_t3=60

# Load configuration file
probe="`cut -d "." -f 2 <<< $(hostname)`"
chprobe_configfile="/var/chprobe/chprobe.cfg"
source $chprobe_configfile

# Remote url stuff
ip_url="http://project-mayhem.se/probes/ip-udp.txt"
urlz="curl -m 3 -s -o /dev/null -w \"%{http_code}\" \$ip_url"
urlcheck=$(eval $urlz)

# Use cached ip if remote server is not responding
if [ $urlcheck -ne 200 ]; then target="$(cat /var/chprobe/ip-udp.txt)"
        else target="$(curl -m 3 -s $ip_url)"
fi

# Check if the target file actually contains any data.. If yes, save it in cache and use it.
if [ -z $target ]; then target="$(cat /var/chprobe/ip-udp.txt)" # Otherwise just use cache file
 else curl -m 3 -s -o /var/chprobe/ip-udp.txt $ip_url
fi

# Daemon settings
if [ $direction = "upstream" ]; then
udpdaemon="/usr/bin/iperf3 -u --client \$target -T \$direction -b \${arr[\$rand]}m -t \$DURATION -p \${portz[\$randport]} -f m 2> /dev/stdout | egrep 'iperf Done' -B 3 | egrep 0.00-\$DURATION | grep -v sender | awk '{print \$1,\$6,\$8,\$10,\$13,\$14.\$15,\$16,\$17,\$18}' | tr -d '(%)|:' | logger -t iperf3udp[\$(echo \$count)] -p \$logfacility"

elif [ $direction = "downstream" ]; then
udpdaemon="/usr/bin/iperf3 -u --client \$target -T \$direction -R -b \${arr[\$rand]}m -t \$DURATION -p \${portz[\$randport]} -f m 2> /dev/stdout | egrep 'iperf Done' -B 3 | egrep 0.00-\$DURATION | grep -v sender | awk '{print \$1,\$6,\$8,\$10,\$13,\$14.\$15,\$16,\$17,\$18}' | tr -d '(%)|:' | logger -t iperf3udp[\$(echo \$count)] -p \$logfacility"
	else echo 'No direction specified, exiting.' && exit 1
fi

# Load the Wi-Fi poller
if [ ! -f $probedir/wifipoller.sh ]; then
    echo "Could not locate wifipoller script."
else
    source $probedir/wifipoller.sh
fi

# Randomize stream bandwidth.
arr[0]="$chprobe_iperf3udp_stream_b1"
arr[1]="$chprobe_iperf3udp_stream_b2"
arr[2]="$chprobe_iperf3udp_stream_b3"
rand=$[ $RANDOM % 3 ]

# Randomize ports to connect to.
portz[0]="5210"
portz[1]="5215"
portz[2]="5220"
portz[3]="5225"
portz[4]="5230"
portz[5]="5235"
portz[6]="5236"
portz[7]="5237"
portz[8]="5238"
portz[9]="5239"
portz[10]="5240"
portz[11]="5241"
portz[12]="5242"
portz[13]="5243"
portz[14]="5244"
portz[15]="5245"
portz[16]="5246"
portz[17]="5247"
portz[18]="5248"
randport=$[ $RANDOM % 18 ]

# Only go into anti-collision loop if the bandwidth is 20 mbit or higher
if [ ${arr[$rand]} -ge 20 ]; then udp_anticollision=1
else udp_anticollision=0
fi

# Assign configured durations
if [ ${arr[$rand]} -eq $chprobe_iperf3udp_stream_b1 ]; then DURATION=$chprobe_iperf3udp_stream_t1
elif [ ${arr[$rand]} -eq $chprobe_iperf3udp_stream_b2 ]; then DURATION=$chprobe_iperf3udp_stream_t2
elif [ ${arr[$rand]} -eq $chprobe_iperf3udp_stream_b3 ]; then DURATION=$chprobe_iperf3udp_stream_t3
fi

# Run tests and avoid collisions
while [ `pgrep -f 'bbk|iperf3|wrk' | wc -w` -ge 30 ];do kill $(pgrep -f "iperf3|bbk|wrk" | awk '{print $1}') && echo "[chprobe_error] We're overloaded with daemons, killing everything" | logger -p local5.err ; done
	if [ $udp_anticollision -eq 1 ]; then
        	while [ `pgrep -f 'bbk|tcp_iperf3|iperf3tcp' | wc -w` -ge 1 ];do echo "[$logtag] bbk or iperf3tcp is running, waiting." | logger -p info && sleep 3
		done
	fi
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[$logtag] Let's see if we can start the udp daemon" | logger -p info
    while iperf3 -c $target -p ${portz[$randport]} -t 1 2> /dev/stdout | grep busy; do randport=$[ $RANDOM % 18 ] && sleep $[ ( $RANDOM % 10 ) + 3]s && echo "[$logtag] server is busy. We slept a bit, now rolling the dice for the port" | logger -p info;done
    echo "[$logtag] udp daemon started - $direction" | logger -p info
	eval $udpdaemon &
        wifi_logger
;;
1)  echo "[$logtag] iperf daemon already running" | logger -p info
          while [ `pgrep -f 'iperf3 --client|bbk_cli' | wc -w` -ge 1 ];do sleep $[ ( $RANDOM % 5 ) + 3]s && echo "[$logtag] waiting cuz either an iperf3 or a bbk daemon is running" | logger -p info;done    
echo "[$logtag] udp daemon started - $direction" | logger -p info
	        eval $udpdaemon &
                wifi_logger
;;
*)  echo "[$logtag] multiple instances of iperf3 udp daemons currently running." | logger -p info
#    kill $(pgrep -f "iperf3 --client" | awk '{print $1}') # Disabled to allow bidirectional UDP tests
    ;;
esac;
