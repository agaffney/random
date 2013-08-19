#!/bin/bash

contains() {
    local n=$#
    local value=${!n}
    local i
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
            return 0
        fi
    }
    return 1
}

message() {
        local line=$1
        shift
        local msg=$@
        echo "${template}:${line}: ${msg}"
}

template=$1

ORIG_IFS=$IFS

if [ -z "$template" ]; then
        echo "You must specify a template"
        exit 1
fi

if [ ! -f $template ]; then
        echo "The specified template '${template}' doesn't exist"
        exit 1
fi

declare -a defined_vars=( )

linenum=0
while read -r fileline; do
        linenum=$((linenum + 1))
        while read -r line; do
                # Blank line
                if echo "$line" | grep -q '^$'; then
                        continue
                fi
                # Initial line
                if echo "$line" | grep -q "^_erbout = ''\$"; then
                        continue
                fi
                # Comment
                if [[ $line =~ '^ *#' ]]; then
                        continue
                fi
                # Ending line
                if echo "$line" | grep -q '^_erbout$'; then
                        continue
                fi
                # Simple string output
                if echo "$line" | grep -q '^_erbout\.concat ".*"$'; then
                        continue
                fi
                # Simple assignment
                foo=$(echo "$line" | grep -o '^[[:space:]]*[a-z0-9_A-Z]\+[[:space:]]*=' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]\+=$//')
                if [ -n "$foo" ]; then
                        defined_vars=( "${defined_vars[@]}" $foo )
                fi
                # Iterator variables
                matches=$(IFS=', '; echo "$line" | grep -o '\(\<do\|{\)[[:space:]]\+|[a-z0-9_A-Z, ]\+|' | sed -e 's/^[^|]*|//' -e 's/|.*$//' | tr ',' ' ')
                if [ -n "$matches" ]; then
                        for match in $matches; do
                                defined_vars=( "${defined_vars[@]}" $match )
                        done
                fi
                # Simple variable replacements
                matches=$(echo "$line" | grep -o '([[:space:]]*[a-z0-9_A-Z]\+')
                if [ -n "$matches" ]; then
                        IFS=$'\n'
                        for match in $matches; do
                                IFS=$ORIG_IFS
                                var=$(echo "$match" | sed -e 's:_erbout\.concat::g' | grep -o '[a-z0-9_A-Z]\+')
                                [[ $var =~ '^([0-9]|scope|_erbout|[A-Z])' ]] && continue
                                IFS=$'\n'
                                if ! contains  "${defined_vars[@]}" $var; then
                                        message $linenum "Simple variable replacement (${var}) without instance variable"
                                fi
                        done
                        IFS=$ORIG_IFS
                fi
                # Use of has_variable?
                match=$(echo "$line" | grep -o 'has_variable\?')
                if [ -n "$match" ]; then
                        message $linenum "Usage of has_variable?() function"
                fi
                # Variable used as object
                match=$(echo "$line" | grep -o "\(^\|([[:space:]]*\)[^.@'\"][a-z0-9_A-Z]\+\." | head -n 1)
                if [ -n "$match" ]; then
                        var=$(echo "$match" | grep -o '[a-z0-9_A-Z]\+\.$' | sed -e 's:\.$::')
                        [[ $var =~ '^([0-9]|scope|_erbout|[A-Z])' ]] && continue
                        if ! contains "${defined_vars[@]}" $var; then
                                message $linenum "Non-instance variable (${var}) used as object"
                        fi
                fi
                # Variable in 'if' statement
                matches=$(echo "$line" | grep -o "^\(el\)\?if *\(.*&&\|.*||\)\? *[a-z0-9_A-Z]\+[^a-z0-9_A-Z?(]")
                if [ -n "$matches" ]; then
                        IFS=$'\n'
                        found=0
                        for match in $matches; do
                                var=$(echo "$match" | grep -o '[a-z0-9_A-Z]\+.$' | sed -e 's:.$::')
                                if ! contains "${defined_vars[@]}" $var; then
                                        found=1
                                fi
                        done
                        IFS=$ORIG_IFS
                        if [ $found = 1 ]; then
                                message $linenum "Non-instance variable (${var}) used in 'if' statement"
                        fi
                fi
        done < <(echo "$fileline" | sed -e 's/; _erbout/\n_erbout/g')
done < <(erb -x -T - -P $template)
