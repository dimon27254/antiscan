#!/bin/sh

ASCN_TEMP_FILE="/tmp/ascn.run"

[ "$type" == "ip6tables" ] && exit
[ "$table" != "filter" ] && exit
[ ! -f "$ASCN_TEMP_FILE" ] && exit

/opt/etc/init.d/S99ascn update_rules 2>/dev/null