PUPPET_LOCKFILE=/var/tmp/puppet-run.lock
PUPPET_BINARY=/usr/bin/puppet
PUPPET_CATALOG_RUN_LOCKFILE=/var/lib/puppet/state/agent_catalog_run.lock
PUPPET_DISABLED_LOCKFILE=/var/lib/puppet/state/agent_disabled.lock
PUPPET_AGENT_CMD_BASE="${PUPPET_BINARY} agent --test --logdest syslog"

LOCK_IDX_PID=0
LOCK_IDX_EXPIRE=1
LOCK_IDX_USER=2
LOCK_IDX_MSG=3

# Log something
log() {
	local msg="$@"
	logger -t "$(basename $0)[$$]" "$msg"
}

# Check our lock file
check_lock() {
	if [[ ! -f $PUPPET_LOCKFILE ]]; then
		return 0
	fi
	# Read lockfile contents into array for easier handling
	IFS=$'\t' read -r -a LOCK_INFO < $PUPPET_LOCKFILE
	if [[ ${LOCK_INFO[$LOCK_IDX_PID]} = -1 ]]; then
		# Puppet is paused
		time_remain=$(( ${LOCK_INFO[$LOCK_IDX_EXPIRE]} - $(date +%s) ))
		if [[ $time_remain -le 0 ]]; then
			# Lock has expired
			remove_lock
			return 0
		fi
		# Lock is still valid
		echo "Puppet is paused by user ${LOCK_INFO[$LOCK_IDX_USER]} for another ${time_remain} second(s)"
		return 1
	elif [[ ${LOCK_INFO[$LOCK_IDX_PID]} -gt 1 ]]; then
		# Someone is using puppet-run
		if ! pid_exists ${LOCK_INFO[$LOCK_IDX_PID]}; then
			# Process no longer exists
			remove_lock
			return 0
		fi
		# Lock is still valid
		echo "The user ${LOCK_INFO[$LOCK_IDX_USER]} is currently running puppet"
		return 2
	else
		# Invalid lock file
		remove_lock
		exit 0
	fi
}

# Writes our lock file
write_lock() {
	local expire=${1:-0}
	local msg=$2
	local pid=$$
	# PID and expire are mutually exclusive
	if [[ $expire -gt 0 ]]; then
		pid=-1
	fi
	echo -e "${pid}\t${expire}\t$(get_user)\t${msg}" > $PUPPET_LOCKFILE
}

# Remove the lock
remove_lock() {
	rm $PUPPET_LOCKFILE 2>/dev/null
}

# Check if specified PID exists
pid_exists() {
	local pid=$1
	kill -0 $pid 2>/dev/null
}

# We only want these scripts to run as root (or via sudo)
is_root_user() {
	if [[ $(id -u) = 0 ]]; then
		return 0
	fi
	return 1
}

# Return the user running the script
get_user() {
	echo ${SUDO_USER:-${USERNAME:-${USER}}}
}

# Convert git branch name into "safe" env name
git_branch_to_puppet_env() {
	local branch=$1
	if [[ $branch == "master" ]]; then
		echo "production"
	else
		# Puppet has certain requirements about environment names, so we munge the branch name
		echo $branch | sed -e 's:[^a-zA-Z0-9_]:_:g'
	fi
}

# Prompts the user and returns 0 if "yes"
prompt_yes_no() {
	local prompt=$1
	local timeout=$2
	local read_cmd="read -p \"${prompt} [y/N]? \""
	if [[ -n $timeout ]]; then
		read_cmd="${read_cmd} -t ${timeout}"
	fi
	read_cmd="${read_cmd} answer"
	eval $read_cmd
	if [[ $answer =~ ^(y|Y|yes)$ ]]; then
		return 0
	fi
	return 1
}
