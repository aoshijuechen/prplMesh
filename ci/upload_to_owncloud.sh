#!/bin/bash
###############################################################
# SPDX-License-Identifier: BSD-2-Clause-Patent
# Copyright (c) 2020 Tomer Eliyahu (Intel)
# This code is subject to the terms of the BSD+Patent license.
# See LICENSE file for more details.
###############################################################

scriptdir="$(cd "${0%/*}" && pwd)"
rootdir=$(realpath "$scriptdir/../")

# shellcheck source=../tools/functions.sh
. "$rootdir/tools/functions.sh"

usage() {
    echo "usage: $(basename "$0") [-hv] <user> <password> <remote-path> <local-path>"
    echo "  options:"
    echo "      -h|--help - display this help."
    echo "      -v|--verbose - enable verbosity"
    echo "      -u|--url - webDAV URL (default https://ftp.essensium.com/owncloud/remote.php/dav/files/USERNAME)"
    echo
    echo "  positional arguments:"
    echo "      remote-path - path in the cloud, relative to the user home to upload"
    echo "      local-path - local file or folder to upload"
    echo ""
    echo "  Credentials are taken from $HOME/.netrc"
    echo "  Make sure it has a line like this:"
    echo "    machine ftp.essensium.com login <user> password <password>"
    echo ""
}

create_dir() {
    # create dir $1 in $OWNCLOUD_URL/$user/.
    # if $2 is true, try to delete any existing dir first.
    #
    # note: parent directories are not created automatically, so make sure
    #       to create them if they don't exist yet.
    #
    # uses:
    #   OWNCLOUD_URL
    #   user
    local dir delete status
    dir="$1"
    delete="$2"
    status=0

    dbg "Create directory: $dir"
    if [ "$delete" = true ] ; then
        curl ${QUIET:+-s -S} -f -n -X DELETE "$OWNCLOUD_URL/$user/$dir" > /dev/null 2>&1
    fi
    curl ${QUIET:+ -s -S} -f -n -X MKCOL "$OWNCLOUD_URL/$user/$dir" || {
        status="$?"
        err "Failed to create dir: $dir (error $status)"
    }
    return "$status"
}

upload_files() {
    # Upload files given as arguments.
    # $1 the directory to upload to (make sure it exists already).
    # $2 the files to upload, comma separated.
    # uses:
    #
    #   OWNCLOUD_URL
    #   user
    local dir files status
    dir="$1"
    files="$2"
    status=0

    curl ${QUIET:+ -s -S} -f -n -T "{$files}" "$OWNCLOUD_URL/$user/$dir/" || {
        status="$?"
        err "Failed to upload files to $dir (error $status)"
    }
    return "$status"
}

move() {
    # move $1 to $2 on remote.
    # if $2 already exists, it's completely overwritten.
    #
    # uses:
    #   OWNCLOUD_URL
    #   user
    local src dst status
    src="$1"
    dst="$2"
    status=0
    dbg "Moving \"$src\" to \"$dst\" on the remote"
    curl ${QUIET:+-s -S} -f -n -X MOVE --header \
         "Destination: $OWNCLOUD_URL/$user/$dst" "$OWNCLOUD_URL/$user/$src" || {
        status="$?"
        err "Failed to move $src to $dst (error $status)"
    }
    return "$status"
}

main() {
    if ! OPTS=$(getopt -o 'hvu:' --long help,verbose,url: -n 'parse-options' -- "$@"); then
        echo echo "Failed parsing options." >&2; usage; exit 1
    fi

    eval set -- "$OPTS"

    while true; do
        case "$1" in
            -h | --help)            usage; exit 0;;
            -v | --verbose)         export VERBOSE=true; QUIET=; shift;;
            -u | --owncloud-url)    OWNCLOUD_URL="$2"; shift 2;;
            -- ) shift; break ;;
            * ) err "unsupported argument $1"; usage; exit 1;;
        esac
    done

    [ -n "$1" ] || { usage; err "Missing remote-path"; exit 1; }
    remote_path="$1"; shift
    [ -n "$1" ] || { usage; err "Missing local-path"; exit 1; }
    local_path="$1"; shift

    info "upload $local_path to $OWNCLOUD_BROWSE_URL/$remote_path/$(basename "$local_path") (using user $user)"
    if ! find "$local_path" -type d -exec \
            realpath {} --relative-to="$(dirname "$local_path")" \; | {
                error=0
                while read -r -s dir; do
                    printf . # show progress
                    create_dir "$remote_path/$dir" || {
                        error="$?"
                        continue
                    }
                    printf . # show progress
                    # get the list of files to upload in the format <file>,<file>,...,<file>
                    files=$(find "$(dirname "$local_path")/$dir/" -type f -maxdepth 1 -print0 | tr '\0' ',' | sed 's/,$//')
                    dbg "$files"
                    [ -n "$files" ] && {
                        upload_files "remote_path/$dir" "$files" || {
                            error="$?"
                        }
                    }
                done
                return $error
            }
    then
        echo
        err "Upload failed"
        return 1
    fi
    echo
    success "Upload success"
}

OWNCLOUD_URL="https://ftp.essensium.com/owncloud/remote.php/dav/files"
OWNCLOUD_BROWSE_URL="https://ftp.essensium.com/owncloud/index.php/apps/files/?dir=/prplmesh/certification"
QUIET=true
user=$(awk '/ftp.essensium.com/{getline; print $4}' ~/.netrc)

main "$@"