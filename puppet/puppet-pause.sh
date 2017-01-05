#!/bin/bash

# Default config values
PAUSE_TIME=
RELEASE=0

usage() {
	cat <<EOF

Usage: $(basename $0) [options] [time]

Options:

	-h, --help         Show this help message
	--release          Releases the puppet lock, if one exists

Arguments:

	time               Length of time to pause puppet for, up to 1 week, should
	                   be specified with s/m/h/d/w suffix
EOF
}

# Source our functions file
func_file="$(dirname $(readlink -f $0))/puppet-functions.sh"
if [[ ! -f $func_file ]]; then
	echo "Cannot find functions file!"
	exit 1
fi
source $func_file

# Parse commandline options
while [[ $# -ge 1 ]]; do
	case $1 in
		-h|--help)
			usage
			exit 0
			;;
		--release)
			RELEASE=1
			shift 1
			;;
		*)
			PAUSE_TIME=$@
			break
			;;
	esac
done

if ! is_root_user; then
	echo "This script must be run by the root user"
	exit 1
fi

if [[ $RELEASE = 1 ]]; then
	remove_lock
else
	if [[ $(get_user) == "root" ]]; then
		echo "This script must be run via sudo as a non-root user, so that it's clear who did the pausing"
		exit 1
	fi

	# Check our time input and convert to seconds
	if [[ ! $PAUSE_TIME =~ ^[0-9]+[smhdw]$ ]]; then
		echo "Invalid time specification: $PAUSE_TIME"
		usage
		exit 1
	fi
	suffix=$(echo "$PAUSE_TIME" | sed -e 's:^.*\([sdhmw]\)$:\1:')
	case $suffix in
		s)
			new_suffix=seconds
			;;
		m)
			new_suffix=minutes
			;;
		h)
			new_suffix=hours
			;;
		d)
			new_suffix=days
			;;
		w)
			new_suffix=weeks
			;;

	esac
	PAUSE_TIME=$(echo "$PAUSE_TIME" | sed -e "s:[smhdw]\$:$new_suffix:")
	expire_time=$(date -d "+${PAUSE_TIME}" +%s)
	if [[ $expire_time -gt $(date -d "+1 week" +%s) ]]; then
		echo "Pause time must be 1 week or less"
		exit 1
	fi

	# Check for existing lock file
	check_lock
	retval=$?
	if [[ $retval = 1 ]]; then
		if ! prompt_yes_no "Do you want to override" 30; then
			exit 0
		fi
	fi
	if [[ $retval = 2 ]]; then
		exit 1
	fi

	write_lock $expire_time
fi
