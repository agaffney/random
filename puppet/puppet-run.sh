#!/bin/bash

# Default config values
APPLY=maybe
ENVIRONMENT=
TAGS=
EXTRA_ARGS=
REPORT=0
UNPAUSE=0

usage() {
	cat <<EOF

Usage: $(basename $0) [options]

Options:

	-h, --help         Show this help message
	--apply [APPLY]    Specifies whether to apply the changes. Valid values are: yes, no, maybe (default)
	-y, --yes          Apply changes, alias for --apply=yes
	-n, --no           Do not apply changes, synonomous with puppet --noop, alias for --apply=no
	-e, --env          Specified puppet environment to run against, defaults to 'production'
	-t, --tags         Allows specifying a list of comma-separated tags for the puppet run
	-r, --report       Specifies that a report should be sent at the end of the run (defaults to off)
	-c, --cron         Enables "cron" mode, which implies other options
	--unpause          Calls 'puppet-pause --release' before running the agent
EOF
}

# Check for and remove a dead puppet catalog run lock
remove_dead_agent_lock() {
	# If there's no lockfile, everything is good
	if [[ ! -e $PUPPET_CATALOG_RUN_LOCKFILE ]]; then
		return 0
	fi
	# If the lockfile is present but empty, just remove it
	if [[ ! -s $PUPPET_CATALOG_RUN_LOCKFILE ]]; then
		rm $PUPPET_CATALOG_RUN_LOCKFILE
		return 0
	fi
	local pid=$(< $PUPPET_CATALOG_RUN_LOCKFILE)
	if ! pid_exists $pid; then
		# No process with PID in lock file, so kill the lock file
		rm $PUPPET_CATALOG_RUN_LOCKFILE
		return 0
	fi
	# The agent appears to be doing a run
	return 1
}

# Check for and kill "old" puppet instance
kill_old_puppet_instance() {
	old_pids=$(pgrep -f 'puppet agent')
	for old_pid in $old_pids; do
		# Check if process has been running for at least a day or at least 3 hours
		if ps -p $old_pid -o etime= | grep -qE '^ *[0-9]+-|[3-9]:[0-9]+:[0-9]+$'; then
			kill $old_pid
			echo "Waiting for old process to die"
			sleep 10s
		fi
	done
}

# Run puppet
run_puppet() {
	log "puppet run initiated by user $(get_user) with arguments: $@"
	$PUPPET_AGENT_CMD_BASE "$@"
	# Grab last line of output from the log and write it to a file that
	# will later be read by the check_puppet.py nagios plugin
	tail -n 1000 /var/log/messages | grep puppet-agent | tail -n 5 | grep 'Could not retrieve catalog\|Finished catalog run' | sed -e 's/^.* puppet-agent\[[0-9]\+\]: //' > /var/lib/puppet/state/last_run_output.txt
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
		--apply)
			APPLY=$2
			shift 2
			;;
		-y|--yes)
			APPLY=yes
			shift
			;;
		-n|--no)
			APPLY=no
			shift
			;;
		-e|--env|--environment)
			ENVIRONMENT=$(git_branch_to_puppet_env $2)
			shift 2
			;;
		-t|--tags)
			TAGS=$2
			shift 2
			;;
		-r|--report)
			REPORT=1
			shift
			;;
		-c|--cron)
			APPLY=yes
			REPORT=1
			shift
			;;
		--unpause|--release)
			UNPAUSE=1
			shift
			;;
		--)
			# Eat the rest of the args and break out
			shift
			EXTRA_ARGS="$@"
			break
			;;
		-*)
			echo "Unrecognized option: $1"
			usage
			exit 1
			;;
		*)
			echo "Unrecognized argument: $1"
			usage
			exit 1
			;;
	esac
done

if ! is_root_user; then
	echo "This script must be run by the root user"
	exit 1
fi

# Check the supplied arguments
if [[ ! $APPLY =~ ^(yes|no|maybe)$ ]]; then
	echo "Invalid value for --apply: $APPLY"
	usage
	exit 1
fi

# Kill any old puppet instances
kill_old_puppet_instance

# Remove dead agent lock
remove_dead_agent_lock

# Release existing lock, if requested
if [[ $UNPAUSE = 1 ]]; then
	/usr/local/bin/puppet-pause --release
fi

# Check for existing lock file
check_lock
if [[ $? != 0 ]]; then
	exit 1
fi

write_lock

# Build our puppet args
PUPPET_ARGS=
if [[ -n $ENVIRONMENT ]]; then
	PUPPET_ARGS="${PUPPET_ARGS} --environment '$ENVIRONMENT'"
fi
if [[ -n $TAGS ]]; then
	PUPPET_ARGS="${PUPPET_ARGS} --tags '${TAGS}'"
fi
if [[ $REPORT = 0 ]]; then
	PUPPET_ARGS="${PUPPET_ARGS} --no-report"
else
	PUPPET_ARGS="${PUPPET_ARGS} --report"
fi
PUPPET_ARGS="${PUPPET_ARGS} ${EXTRA_ARGS}"

# Run puppet
if [[ $APPLY = yes ]]; then
	run_puppet $PUPPET_ARGS
elif [[ $APPLY = no ]]; then
	run_puppet $PUPPET_ARGS --noop
elif [[ $APPLY = maybe ]]; then
	run_puppet $PUPPET_ARGS --noop
	if prompt_yes_no "Apply changes" 300; then
		run_puppet $PUPPET_ARGS
	fi
fi

remove_lock
