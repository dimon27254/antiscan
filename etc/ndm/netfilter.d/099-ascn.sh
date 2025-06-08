#!/bin/sh

ASCN_TEMP_FILE="/tmp/ascn.run"

[ "$type" == "ip6tables" ] && exit
[ "$table" != "filter" ] && exit
[ ! -f "$ASCN_TEMP_FILE" ] && exit
[ -z "$(ipset -q list ascn_ips)" ] || [ -z "$(ipset -q list ascn_candidates)" ] || [ -z "$(ipset -q list ascn_subnets)" ] && exit

/opt/etc/init.d/S99ascn update_rules 2>/dev/null