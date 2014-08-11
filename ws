#!/usr/bin/env bash

function script_name {
    basename "$0"
}

function sed_escape {
    echo "$*" | sed -e 's/[]\/()$*.^|[]/\\&/g'
}

function forward_stdin {
    local method="$1"; shift
    [[ -t 0 ]] || cat
    [ "$method" != "" ] && $method $*
}

function in_array {
    local element="$1"; shift
    for item in $*; do [ "$item" = "$element" ] && return 0; done
    return 1
}

function is_empty {
    [ "$#" -eq 0 ]
}

function is_empty_directory {
    [ "$(ls -A "$1")" = "" ]
}

function any_of {
    local method="$1"; shift
    for item in $*; do $method "$item" && return 0; done
    return 1
}

function none_of {
    local method="$1"; shift
    for item in $*; do $method "$item" && return 1; done
    return 0
}

function join {
    local IFS="$1"; shift; echo "$*";
}

function checksum {
    if $(which md5sum &>/dev/null); then
        echo "$1" | md5sum | awk '{print $1}'
    elif $(which md5 &>/dev/null); then
        echo "$1" | md5
    else
        die "can't find md5 or md5sum in path"
    fi
}

function enable_termination_from_functions {
    trap "exit 1" TERM
    trap "exit 0" QUIT
    export TOP_PID=$$
}

function die {
    echo 1>&2
    echo "$*" | fold -s 1>&2
    echo 1>&2
    kill -s TERM $TOP_PID
}

function finish {
    echo "$*" | fold -s 1>&2
    kill -s QUIT $TOP_PID
}

function warn {
    echo "warning: $*" | fold -s 1>&2
}

function debug {
    has_option "debug" || return
    echo "debug: $*" | fold -s 1>&2
}

function message {
    echo "$*" | fold -s 1>&2
    [[ -t 0 ]] || fold -s 1>&2
}

function upcase {
    echo "$1" | tr 'a-z' 'A-Z'
}

function relative_path_for {
    local path="$1"
    local prefix="${2:-$HOME}"
    echo ${1#$prefix} | sed 's/^\///'
}

function strip_from_path {
    echo "$PATH" | awk -v RS=: -v ORS=: -v item="$1" \
        '$0 ~ item {next} {print}' | sed 's/:*$//'
}

function set_option {
    is_valid_option "$1" || warn "set_option called for unknown option: $1"
    export "_option_$1"="$2"
}

function get_option {
    is_valid_option "$1" || warn "get_option called for unknown option: $1"
    local key="_option_$1"
    echo "${!key}"
}

function has_option {
    [ "$(get_option "$1")" = "yes" ] || [ "$(get_option "$1")" = "true" ]
}

function load_options {
    source "$1"
}

function save_option {
    local file="$1"
    local key="_option_$2"
    local value="\"$3\""

    [ ! -f $file ] && touch $file

    if grep -q "$key\=" $file; then
        local escaped_value="$(sed_escape "$value")"
        sed -i "" "s/^.*$key\=.*$/export $key\=$escaped_value/" $file
    else
        echo "export $key=$value" >> $file
    fi
}

function is_valid_option {
    local settings=("host" "force" "debug" "shim_system_binaries"
        "skip_remote_cleanup" "use_login_shell")
    in_array "$1" "${settings[@]}"
}

function set_options_from_args {
    for arg in $*; do
        [ "$arg" = "--" ] && return
        [[ "$arg" == *=* ]] || continue

        local key="${arg%=*}"
        is_valid_option "$key" || continue

        local value="${arg#*=}"
        set_option "$key" "$value"
    done
}

function remove_options_from_args {
    local -a output
    local -a passthrough

    for arg in $*; do
        if [ "$arg" = "--" ]; then
            passthrough="true"
        elif [[ "$passthrough" = "" && "$arg" == *=* ]]; then
            local key="${arg%=*}"
            is_valid_option "$key" || output=("${output[@]}" "$arg")
        else
            output=("${output[@]}" "$arg")
        fi
    done

    echo "${output[@]}"
}

function set_remote {
    export SSH_HOST="$1"
}

function on_remote {
    ssh -qt $SSH_HOST "$*"
}

function remote_shell {
    ssh -qt $SSH_HOST "cd \"$1\" ; bash -login"
}

function is_mounted {
    mount | grep -q "$1"
}

function mount_remote {
    local remote="$SSH_HOST:$1"
    local local="$2"

    is_mounted "$1" && return

    [ -d "$mount_path" ] || mkdir -p "$mount_path" \
        || die "Unable to create $mount_path"
    local sshfs_options="-o reconnect -o uid=$(id -u) -o gid=$(id -g)"
    sshfs $sshfs_options $remote $local &>/dev/null \
        || die "Unable to mount $remote at $local"
}

function unmount_remote {
    is_mounted "$1" && umount "$1"
}

function on_remote_directory_exists {
    on_remote "test -d \"$1\""
}

function on_remote_directory_is_empty {
    [ "$(on_remote "cd \"$1\" ; find .")" = "." ]
}

function on_remote_get_git_url {
    on_remote "cd \"$1\"; git config --get remote.origin.url"
}

function maybe_host {
    local host="$1"

    if [[ "$host" = "-" || "$host" = "" ]]; then
        host="$(get_option "host")"
        [ "$host" = "" ] && die "No default host has been set."
    fi

    echo "$host"
}

function maybe_namespace {
    echo "$1" | sed 's/^\/*/\//' | sed 's/\/*$//'
}

function initialize {
    export CONFIG_PATH="$WORKSPACE_HOME/.config"
    export SETTINGS_FILE="$WORKSPACE_HOME/.config/settings"
    export SHIMS_PATH="$WORKSPACE_HOME/.config/shims"
    export PATH="$(strip_from_path "$SHIMS_PATH")"

    [ -d "$SHIMS_PATH" ] || mkdir -p "$SHIMS_PATH"
    [ -f "$SETTINGS_FILE" ] && load_options "$SETTINGS_FILE"
}

function check_for_conflicts_before_clone {
    local repository="$1"
    local remote_path="$2"

    on_remote_directory_exists "$remote_path" || return 0
    on_remote_directory_is_empty "$remote_path" && return 0

    local remote_git_url="$(on_remote_get_git_url "$remote_path")"
    [ "$remote_git_url" = "$repository" ] && return 1
    [ "$remote_git_url" = "" ] \
        && die "$remote_path exists on $SSH_HOST and is not empty."
    die "$remote_path exists on $SSH_HOST and is already a git repository pointed at $remote_git_url"
}

function clone_repository_on_remote {
    local repository="$1"
    local remote_path="$2"

    check_for_conflicts_before_clone "$repository" "$remote_path" || return
    on_remote "test -d \"$remote_path\" || mkdir -p \"$remote_path\"" \
        || die "Unable to create $remote_path on $SSH_HOST"
    on_remote "git clone -q \"$repository\" \"$remote_path\"" \
        || die "Unable to clone $repository into $remote_path on $SSH_HOST"
}

function project_set_state {
    local project_path="$1"
    local state="$2"

    echo "$state" > "$project_path/state"
    message "$(project_name "$project_path") ($state)"
}

function project_list {
    ls -d "$CONFIG_PATH"/*.project 2>/dev/null
}

function project_host {
    cat "$1/host"
}

function project_state {
    cat "$1/state"
}

function project_repository {
    cat "$1/repository"
}

function project_mount_path {
    readlink "$1/mount"
}

function project_remote_path {
    relative_path_for "$(project_mount_path "$1")"
}

function project_name {
    relative_path_for "$(project_mount_path "$1")" "$WORKSPACE_HOME"
}

function project_namespace {
    cat "$1/namespace"
}

function find_project_by_path {
    local target="$1"

    [ -d "$target" ] || return 1

    [[ "$target" = "$CONFIG_PATH"/*.project* ]] && echo "$target" && return 0

    local target_path="$(cd "$target"; echo "$PWD")"
    [[ "$target_path" = "$WORKSPACE_HOME"* ]] || return 1

    for project in $(project_list); do
        local mount_path="$(project_mount_path "$project")"
        [[ "$target_path" = "$mount_path"* ]] && echo $project && return 0
    done

    return 1
}

function find_project_by_name {
    local target="$1"

    [ -d "$WORKSPACE_HOME/$target" ] || return
    find_project_by_path "$WORKSPACE_HOME/$target"
}

function find_project_by_repository {
    local target="$1"

    for project in $(project_list); do
        local repository_path="$(project_repository "$project")"
        [ "$repository_path" = "$target" ] && echo $project && return 0
    done

    return 1
}

function find_project {
    local target="$1"

    find_project_by_path "$target" \
        || find_project_by_name "$target" \
        || find_project_by_repository "$target" \
        || die "Can't find a project for $target"
}

function find_all_projects_by_host {
    [[ "$1" == @* ]] || return

    local search="$(echo "${1#@}" | tr '%' '*')"

    for project in $(project_list); do
        [[ "$(project_host "$project")" == $search ]] && echo $project
    done
}

function find_all_projects_by_path {
    [[ "$1" == @* ]] && return

    local search="$(echo "$1" | tr '%' '*')"
    for path in $search; do find_project_by_path "$path"; done
}

function find_all_projects_by_name {
    local search="$(echo "$1" | tr '%' '*')"

    for project in $(project_list); do
        [[ "$(project_name "$project")" == $search ]] && echo $project
    done
}

function find_all_projects_by_repository {
    local search="$(echo "$1" | tr '%' '*')"

    for project in $(project_list); do
        [[ "$(project_repository "$project")" == $search ]] && echo $project
    done
}

function find_all_projects {
    find_all_projects_by_host "$1" \
        | forward_stdin "find_project_by_path" "$1" \
        | forward_stdin "find_all_projects_by_name" "$1" \
        | forward_stdin "find_all_projects_by_repository" "$1" \
        | sort | uniq
}

function each_project {
    local method="$1"; shift

    for token in "$*"; do
        for project in $(find_all_projects "$token"); do
            $method "$project"
        done
    done
}

function confirm_remove {
    local target="$1"
    local project_path="$2"
    local name="$(project_name "$project_path")"
    local host="$(project_host "$project_path")"

    message <<END
Removing this project will delete the associated cloned repository on "$host". You will lose anything that hasn't been pushed upstream, including things like database passwords that aren't usually kept in the repository by sane individuals.

If you want to keep these files on the remote, re-run $(script_name) with the "skip_remote_cleanup" option:

    $(script_name) remove $target skip_remote_cleanup=yes

To confirm this wanton distruction and delete the cloned repository on "$host", please type in the project name to proceed:

END

    read -e -p "Confirm project name ($name): " "confirmation"
    [ "$confirmation" = "$name" ] || die "Aborted."
}

function is_shell_builtin {
    local command="$1"

    local builtins=("alias" "bg" "bind" "break" "builtin" "cd" "command"
        "compgen" "complete" "continue" "declare" "dirs" "disown" "echo"
        "enable" "eval" "exec" "exit" "export" "fc" "fg" "getopts" "hash"
        "help" "history" "jobs" "kill" "let" "local" "logout" "popd"
        "printf" "pushd" "pwd" "read" "readonly" "return" "set" "shift"
        "shopt" "source" "suspend" "test" "times" "trap" "type" "typeset"
        "ulimit" "umask" "unalias" "unset" "wait")

    in_array "$command" "${builtins[@]}"
}

function is_system_binary {
    local command="$1"

    local paths=(/bin /sbin /usr/sbin)

    for path in ${paths[@]}; do
        [ -d $path ] || continue
        for item in $path/*; do
            [[ -f "$item" && -x "$item" ]] || continue
            [ "${item#$path/}" = "$command" ] && return 0
        done
    done

    return 1
}

function shim_list {
    is_empty_directory $SHIMS_PATH && return
    for shim in $SHIMS_PATH/*; do echo "$(basename $shim)"; done
}

function shim_add {
    for command in $*; do
        local shim_path="$SHIMS_PATH/$command"

        is_shell_builtin "$command" \
            && die "Can't shim a shell builtin: $command"

        none_of "has_option" "force" "shim_system_binaries" \
            && is_system_binary "$command" \
            && die "Can't shim a system binary: $command"

        cat >"$shim_path" <<END
#!/usr/bin/env bash
exec $0 use_login_shell="$(get_option "use_login_shell")" -- exec $command \$*
END
        chmod 755 "$shim_path"
    done
}

function shim_delete {
    for command in $*; do
        local shim_path="$SHIMS_PATH/$command"
        [ -f "$shim_path" ] && rm -f "$shim_path"
    done
}

function run {
    local action="$1"; shift

    initialize

    case $action in
        set|s) run_set $* ;;
        get|g) run_get $* ;;
        add|a) run_add $* ;;
        remove|rm) run_remove $* ;;
        up|u) each_project "run_up" $* ;;
        down|d) each_project "run_down" $* ;;
        restore) run_restore $* ;;
        info|i) each_project "run_info" $* ;;
        list|ls) run_list $* ;;
        shim) run_shim $* ;;
        unshim) run_unshim $* ;;
        exec|e) run_exec $* ;;
        shell|sh) run_shell $* ;;
        init) run_init $* ;;
        *) run_help $* ;;
    esac
}

function run_set {
    local key="$1"
    local value="$2"

    is_valid_option "$key" || die "unknown setting: $key"
    save_option "$SETTINGS_FILE" "$key" "$value"
}

function run_get {
    local key="$1"

    is_valid_option "$key" || die "unknown setting: $key"
    message "$(get_option "$key")"
}

function run_add {
    local repository="$1"
    local host="$(maybe_host "$2")"
    local namespace="$(maybe_namespace "$3")"

    local project_path="$CONFIG_PATH/$(checksum $repository).project"
    local project_name="$(basename "$repository" | sed s/\.git$//)"

    local mount_path="$WORKSPACE_HOME$namespace/$project_name"

    local remote_workspace_home="$(relative_path_for "$WORKSPACE_HOME")"
    local remote_path="$remote_workspace_home$namespace/$project_name"

    set_remote "$host"
    clone_repository_on_remote "$repository" "$remote_path"

    [ -d "$project_path" ] && die "A project for $repository is already set up at $(project_mount_path "$project_path")"
    
    mkdir -p $project_path || die "Unable to create $project_path"

    [ -d "$mount_path" ] || mkdir -p $mount_path \
        || die "Unable to create $mount_path"

    echo "$repository" > "$project_path/repository"
    echo "$host" > "$project_path/host"
    echo "$namespace" > "$project_path/namespace"
    echo "new" > "$project_path/state"

    [ -L "$project_path/mount" ] \
        || ln -s "$mount_path" "$project_path/mount" \
        || die "Unable to symlink $mount_path to $project_path/mount"

    run_up "$mount_path"
}

function run_remove {
    local target="$1"
    local project_path="$(find_project "$target")"
    local namespace="$(project_namespace "$project_path")"

    any_of "has_option" "skip_remote_cleanup" "force" \
        || confirm_remove "$target" "$project_path"

    run_down "$1"
    has_option "skip_remote_cleanup" \
        || on_remote rm -rf "$(project_remote_path "$project_path")"
    rmdir "$(project_mount_path "$project_path")"
    rm -rf "$project_path"

    [ "$namespace" = "" ] && return 0
    is_empty_directory "$WORKSPACE_HOME/$namespace" || return 0
    rmdir "$WORKSPACE_HOME/$namespace"
}

function run_up {
    local project_path="$(find_project "$1")"
    local mount_path="$(project_mount_path "$project_path")"
    local remote_path="$(project_remote_path "$project_path")"

    set_remote "$(project_host "$project_path")"
    mount_remote "$remote_path" "$mount_path" && \
        project_set_state "$project_path" "up"
}

function run_down {
    local project_path="$(find_project "$1")"
    local mount_path="$(project_mount_path "$project_path")"

    set_remote "$(project_host "$project_path")"
    unmount_remote "$mount_path" && project_set_state "$project_path" "down"
}

function run_restore {
    local result=0

    for project in $(project_list); do
        local state="$(project_state "$project")"
        if [ "$state" = "up" ]; then
            run_up "$project" || result=1
        elif [ "$state" = "down" ]; then
            run_down "$project" || result=1
        fi
    done

    return $result
}

function run_info {
    local project_path="$(find_project "$1")"
    message <<END
repository: $(project_repository "$project_path")
path: $(project_mount_path "$project_path")
host: $(project_host "$project_path")
state: $(project_state "$project_path")

END
}

#
# TODO: Add format option, default to just listing projects by name.
#
function run_list {
    for project in $(project_list); do
        local name="$(project_name "$project")"
        local host="$(project_host "$project")"
        local state="$(project_state "$project")"
        message "$name ($state) on $host"
    done
}

#
# TODO: Add a remote_only option to limit commands to *only* run on the
# remote machine.
#
function run_shim {
    if [ $# -eq 0 ]; then
        shim_list
    else
        shim_add $*
    fi
}

function run_unshim {
    shim_delete $*
}

function run_init {
    echo "export PATH=\"$SHIMS_PATH:\$PATH\""
}

function run_exec {
    local project_path="$(find_project_by_path "$PWD")"

    if [ "$project_path" = "" ]; then
        exec $*
    else
        local mount_path="$(project_mount_path "$project_path")"
        local remote_path="$(project_remote_path "$project_path")"
        local relative_path="$(relative_path_for "$PWD" "$mount_path")"
        local combined_path="$remote_path/$relative_path"

        set_remote "$(project_host "$project_path")"
        on_remote "(cd "$combined_path" ; $*)"
    fi
}

function run_shell {
    local project_path="$(find_project_by_path "$PWD")"

    [ "$project_path" = "" ] && die "Not in a workspace-managed project."

    local mount_path="$(project_mount_path "$project_path")"
    local remote_path="$(project_remote_path "$project_path")"
    local relative_path="$(relative_path_for "$PWD" "$mount_path")"
    local combined_path="$remote_path/$relative_path"

    set_remote "$(project_host "$project_path")"
    remote_shell "$combined_path"
}

function run_help {
    case "$1" in
        set|s) help_set ;;
        get|g) help_get ;;
        add|a) help_add ;;
        remove|rm) help_remove ;;
        up|u) help_up ;;
        down|d) help_down ;;
        restore) help_restore ;;
        info|i) help_info ;;
        list|ls) help_list ;;
        shim) help_shim ;;
        unshim) help_unshim ;;
        exec|e) help_exec ;;
        shell|sh) help_shell ;;
        *) help_usage ;;
    esac
}

function help_set {
    message <<END
usage: $(script_name) set [option] [value]

Configures the workspace script; settings configured here are persisted to disk. Any setting may also be specified on the command line as an "option-value" pair Valid settings are: 

host: A default host for SSH.

skip_remote_cleanup: When removing a project, don't delete the copy of the repository on the remote machine.

use_login_shell: Force a login shell for all SSH commands.

END
}

function help_get {
    message <<END
usage: $(script_name) get [option]

Returns the current value for [option]; most useful is probably "$(script_name) get host"

END
}

function help_add {
     message <<END
usage: $(script_name) add [repository] [host] [namespace]

Adds a project to workspace. Functionally, this means cloning a repository on a remote machine, and then mounting that via sshfs under ${WORKSPACE_HOME}:
   
    # Check out Mizuno for development on the "javabox.local" machine,
    # and mount it under "$WORKSPACE_HOME/mizuno"

    $(script_name) add git@github.com:matadon/mizuno.git javabox.local

    # For clients, it's nice to keep them separate. So we can set them up
    # inside their own namespace. This mounts a client project under
    # "$WORKSPACE_HOME/clients/project" on "clientbox"

    $(script_name) add git@github.com:bigcorp/project.git clientbox clients

    # If you have a go-to machine for project work, you can set that as the
    # default host as well:

    $(script_name) set host devbox.local
    $(script_name) git@github.com:dobbs/slack.git

    # You can still use namespaces, even with a default host:

    $(script_name) set host devbox.local
    $(script_name) git@github.com:dobbs/slack.git - slackers

After adding a project, you can manage the sshfs mount with the "up", "down", and "restore" commands, and run commands on the remote vie "exec", "shell", and most importantly, "shim".

END
}

function help_remove {
     message <<END
usage: $(script_name) remove [project | repository]

Completely deletes a project, including removing the files on the remote machine:

    $(script_name) remove only-copy-of-bobs-thesis

If you want to keep the remote repository intact, run with "skip_remote_cleanup=yes":

    $(script_name) remove client-project skip_remote_cleanup=yes

Like "$(script_name) down", but in reverse.

END
}

function help_up {
     message <<END
usage: $(script_name) up [project | host | repository]

Like "$(script_name) down", but in reverse.

END
}

function help_down {
     message <<END
usage: $(script_name) down [project | host | repository]

Unmounts projects, without deleting repositories or making other changes.  This allows you to disconnect from hosts when you don't need to have them mounted, and reconnect when you do by calling "$(script_name) up".

Using the '%' wildcard, and the '@' prefix (which denotes hosts), you can bring multiple projects up or down based on the hostname, repository name, or namespace.

    # Unmount all the projects on a single machine.
    $(script_name) down @workbox.workdomain

    # Unmount every project on the .local mDNS domain.
    $(script_name) down @%.local

    # Unmount every project you're working on for Colossus.
    $(script_name) down colossus/%

    # Unmount every project on Bob's Github. Because screw that guy.
    $(script_name) down %github.com/bob/%

END
}

function help_restore {
     message <<END
usage: $(script_name) restore

We live in an uncertain world.

Machines reboot, SSH mounts go offline due to network problems, and people put butter in their coffee for health reasons.

Projects can be marked as "up" or "down". Restore re-mounts all "up" projects, and ensures that "down" projects aren't mounted.

END
}

function help_info {
     message <<END
usage: $(script_name) info [project...]

Provides detailed information for each project: mount path, repository, hostname, and state.

END
}

function help_list {
     message <<END
usage: $(script_name) list

Lists all the projects managed by workspace.

END
}

function help_shim {
     message <<END
usage: $(script_name) shim [command...]

Adds a shim for running commands on remote machines if and only if you are in a workspace; if not, the command will run on the local machine, like so:

    (~/workspace/project) $ hostname

    local

    (~/workspace/project) $ ws shim hostname
    (~/workspace/project) $ hostname

    remote

    (~/workspace/project) $ cd ~ 
    (~) $ hostname

    local

Shims can be created for any command except for shell builtins. By default, workspace will refuse to create a shim for any of the files in "/bin", "/sbin", and "/usr/sbin", but this behavior can be overridden with the "shim_system_binaries=yes" or "force="yes" options:

    $ ws shim ls

    Can't shim a system binary: ls

    $ ws shim ls force=yes

You can also shim multiple commands in one shot:

    $ ws shim rails rake bundle zeus

Running the command with no arguments will give you a list of current shims.

END
}

function help_unshim {
    message <<END
usage: $(script_name) unshim [command...]

Removes a shim created by "$(script_name) shim".

END
}

function help_exec {
    message <<END
usage: $(script_name) exec [options]

Runs a single command on the remote machine for the current workspace. Pass "use_login_shell=yes" as an option to run the command in a login shell:

    $(script_name) exec whoami use_login_shell=yes

If you want to pass options to the remote script, add them after a double-dash:

    $(script_name) exec -- my_command my_choice=cake

END
}

function help_shell {
    message <<END
usage: $(script_name) shell

Starts an interactive shell on the remote machine for the current workspace.

END
}

function help_usage {
    message <<END
Manages development environments on remote or virtual machines

usage: $(script_name) [command]

Where command is one of: set, get, add, remove, up, down, restore, info, list, shim, unshim, exec, shell, or help

Information and examples for each command can be found with:

    $(script_name) help [command]

END
}

export WORKSPACE_HOME=${WORKSPACE_HOME:-$HOME/ws}

# Add line numbers in xtrace.
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

enable_termination_from_functions
set_options_from_args "$*"
run $(remove_options_from_args "$*") 2>&1
