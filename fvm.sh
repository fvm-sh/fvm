# Flutter Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile
#
# Implemented by hyiso <mylaoda@gmail.com>
# Inspired by fvm https://github.com/fvm-sh/fvm

# "local" warning, quote expansion warning, sed warning, `local` warning
# shellcheck disable=SC2039,SC2016,SC2001,SC3043
{ # this ensures the entire script is downloaded #

# shellcheck disable=SC3028
FVM_SCRIPT_SOURCE="$_"

FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-"https://storage.googleapis.com"}"
FLUTTER_RELEASE_BASE_URL="${FLUTTER_STORAGE_BASE_URL}/flutter_infra_release/releases"

fvm_is_zsh() {
  [ -n "${ZSH_VERSION-}" ]
}

fvm_stdout_is_terminal() {
  [ -t 1 ]
}

fvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

fvm_cd() {
  \cd "$@"
}

fvm_err() {
  >&2 fvm_echo "$@"
}

fvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

fvm_has() {
  type "${1-}" >/dev/null 2>&1
}

fvm_command_info() {
  local COMMAND
  local INFO
  COMMAND="${1}"
  if type "${COMMAND}" | fvm_grep -q hashed; then
    INFO="$(type "${COMMAND}" | command sed -E 's/\(|\)//g' | command awk '{print $4}')"
  elif type "${COMMAND}" | fvm_grep -q aliased; then
    # shellcheck disable=SC2230
    INFO="$(which "${COMMAND}") ($(type "${COMMAND}" | command awk '{ $1=$2=$3=$4="" ;print }' | command sed -e 's/^\ *//g' -Ee "s/\`|'//g"))"
  elif type "${COMMAND}" | fvm_grep -q "^${COMMAND} is an alias for"; then
    # shellcheck disable=SC2230
    INFO="$(which "${COMMAND}") ($(type "${COMMAND}" | command awk '{ $1=$2=$3=$4=$5="" ;print }' | command sed 's/^\ *//g'))"
  elif type "${COMMAND}" | fvm_grep -q "^${COMMAND} is /"; then
    INFO="$(type "${COMMAND}" | command awk '{print $3}')"
  else
    INFO="$(type "${COMMAND}")"
  fi
  fvm_echo "${INFO}"
}

fvm_curl_libz_support() {
  curl -V 2>/dev/null | fvm_grep "^Features:" | fvm_grep -q "libz"
}

fvm_curl_use_compression() {
  fvm_curl_libz_support && fvm_version_greater_than_or_equal_to "$(fvm_curl_version)" 7.21.0
}

fvm_download() {
  local CURL_COMPRESSED_FLAG
  if fvm_has "curl"; then
    if fvm_curl_use_compression; then
      CURL_COMPRESSED_FLAG="--compressed"
    fi
    curl --fail ${CURL_COMPRESSED_FLAG:-} -q "$@"
  elif fvm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(fvm_echo "$@" | command sed -e 's/--progress-bar /--progress=bar /' \
                            -e 's/--compressed //' \
                            -e 's/--fail //' \
                            -e 's/-L //' \
                            -e 's/-I /--server-response /' \
                            -e 's/-s /-q /' \
                            -e 's/-sS /-nv /' \
                            -e 's/-o /-O /' \
                            -e 's/-C - /-c /')
    # shellcheck disable=SC2086
    eval wget $ARGS
  fi
}

fvm_has_system_flutter() {
  [ "$(fvm deactivate >/dev/null 2>&1 && command -v flutter)" != '' ]
}

fvm_is_version_installed() {
  local VERSION="${1-}"
  if [ -z "${VERSION}" ]; then
    return 1
  fi
  local FVM_FLUTTER_BINARY
  FVM_FLUTTER_BINARY='flutter'
  if [ "_$(fvm_get_os)" = '_windows' ]; then
    FVM_FLUTTER_BINARY='flutter.bat'
  fi
  if [ -x "$(fvm_version_path "${VERSION}" 2>/dev/null)/bin/${FVM_FLUTTER_BINARY}" ]; then
    return 0
  fi
  return 1
}

fvm_tree_contains_path() {
  local tree
  tree="${1-}"
  local flutter_path
  flutter_path="${2-}"

  if [ "@${tree}@" = "@@" ] || [ "@${flutter_path}@" = "@@" ]; then
    fvm_err "both the tree and the flutter path are required"
    return 2
  fi

  local previous_pathdir
  previous_pathdir="${flutter_path}"
  local pathdir
  pathdir=$(dirname "${previous_pathdir}")
  while [ "${pathdir}" != '' ] && [ "${pathdir}" != '.' ] && [ "${pathdir}" != '/' ] &&
      [ "${pathdir}" != "${tree}" ] && [ "${pathdir}" != "${previous_pathdir}" ]; do
    previous_pathdir="${pathdir}"
    pathdir=$(dirname "${previous_pathdir}")
  done
  [ "${pathdir}" = "${tree}" ]
}

# Traverse up in directory tree to find containing folder
fvm_find_up() {
  local path_
  path_="${PWD}"
  while [ "${path_}" != "" ] && [ ! -f "${path_}/${1-}" ]; do
    path_=${path_%/*}
  done
  fvm_echo "${path_}"
}

# Obtain flutter version from flutter.version file
fvm_flutter_version() {
  export FVM_FLUTTER_VERSION=''
  local FLUTTER_VERSION_FILE
  FLUTTER_VERSION_FILE="$(fvm_find_up 'flutter.version')/flutter.version"
  if [ ! -e "${FLUTTER_VERSION_FILE}" ]; then
    if [ "${FVM_SILENT:-0}" -ne 1 ]; then
      fvm_err "No flutter.version file found"
    fi
    return 1
  fi
  FVM_FLUTTER_VERSION="$(command head -n 1 "${FLUTTER_VERSION_FILE}" | command tr -d '\r')" || command printf ''
  if [ -z "${FVM_FLUTTER_VERSION}" ]; then
    if [ "${FVM_SILENT:-0}" -ne 1 ]; then
      fvm_err "Warning: empty flutter.version file found at \"${FLUTTER_VERSION_FILE}\""
    fi
    return 2
  fi
  if [ "${FVM_SILENT:-0}" -ne 1 ]; then
    fvm_echo "Found '${FLUTTER_VERSION_FILE}' with version <${FVM_FLUTTER_VERSION}>"
  fi
}

fvm_curl_version() {
  curl -V | command awk '{ if ($1 == "curl") print $2 }' | command sed 's/-.*$//g'
}

fvm_version_greater_than_or_equal_to() {
  command awk 'BEGIN {
    if (ARGV[1] == "" || ARGV[2] == "") exit(1)
    split(ARGV[1], a, /\./);
    split(ARGV[2], b, /\./);
    for (i=1; i<=3; i++) {
      if (a[i] && a[i] !~ /^[0-9]+$/) exit(2);
      if (a[i] < b[i]) exit(3);
      else if (a[i] > b[i]) exit(0);
    }
    exit(0)
  }' "${1#v}" "${2#v}"
}

fvm_version_path() {
  local VERSION
  VERSION="${1-}"
  if [ -z "${VERSION}" ]; then
    fvm_err 'version is required'
    return 3
  else
    fvm_echo "${FVM_DIR}/versions/${VERSION}"
  fi
}

fvm_ensure_version_installed() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="${1-}"
  local IS_VERSION_FROM_FLUTTER_VERSION_FILE
  IS_VERSION_FROM_FLUTTER_VERSION_FILE="${2-}"
  if [ "${PROVIDED_VERSION}" = 'system' ]; then
    if fvm_has_system_flutter; then
      return 0
    fi
    fvm_err "N/A: no system version of flutter is installed."
    return 1
  fi
  local LOCAL_VERSION
  local EXIT_CODE
  LOCAL_VERSION="$(fvm_resolve_version "${PROVIDED_VERSION}")"
  EXIT_CODE="$?"
  local FVM_VERSION_DIR
  if [ "${EXIT_CODE}" != "0" ] || ! fvm_is_version_installed "${LOCAL_VERSION}"; then
    fvm_err "N/A: version \"${PROVIDED_VERSION}\" is not yet installed."
    fvm_err ""
    if [ "${IS_VERSION_FROM_FLUTTER_VERSION_FILE}" != '1' ]; then
      fvm_err "You need to run \`fvm install ${PROVIDED_VERSION}\` to install and use it."
    else
      fvm_err 'You need to run `fvm install` to install and use the flutter version specified in `flutter.version`.'
    fi
    return 1
  fi
}

# Expand a version using the version cache
fvm_resolve_version() {
  local PATTERN
  PATTERN="${1-}"
  # The default version is the current one
  if [ -z "${PATTERN}" ]; then
    PATTERN='current'
  fi
  if [ "${PATTERN}" = "current" ]; then
    fvm_current
    return $?
  fi
  fvm_echo "${PATTERN}"
}

fvm_current() {
  local FVM_CURRENT_FLUTTER_PATH
  FVM_CURRENT_FLUTTER_PATH="$(command which flutter 2>/dev/null)"
  if [ -z "$FVM_CURRENT_FLUTTER_PATH" ]; then
    fvm_echo 'none'
  elif fvm_tree_contains_path "${FVM_DIR}" "${FVM_CURRENT_FLUTTER_PATH}"; then
    fvm_echo "${FVM_CURRENT_FLUTTER_PATH}" | command awk -F '/' '{print $(NF-2)}'
  else
    fvm_echo 'system'
  fi
}

fvm_ls_remote() {
  local CHANNEL
  CHANNEL="${1-}"
  local PATTERN
  PATTERN="${2-}"
  if [ "@${CHANNEL}@" != "@@" ]; then
    case "${CHANNEL}" in
      stable) CHANNEL="stable" ;;
      beta) CHANNEL="beta" ;;
      dev) CHANNEL="dev" ;;
      *) CHANNEL="" ;;
    esac
  fi
  local FVM_OS
  FVM_OS="$(fvm_get_os)"
  if [ "_${FVM_OS}" = "_unsupported" ]; then
    fvm_err "Currently there is no support for this os with flutter."
    return 1
  fi
  if [ "@${PATTERN}@" != "@@" ]; then
    PATTERN="flutter_${FVM_OS}_${PATTERN}"
  fi

  local FVM_LS_REMOTE_EXIT_CODE
  FVM_LS_REMOTE_EXIT_CODE=0
  
  local FVM_LS_REMOTE_OUTPUT
  FVM_LS_REMOTE_OUTPUT="$(fvm_releases | fvm_grep "${CHANNEL}" | fvm_grep "${PATTERN}")"
  FVM_LS_REMOTE_EXIT_CODE=$?

  VERSIONS="$(fvm_version_from_archive "${FVM_LS_REMOTE_OUTPUT}" \
   | command awk -F "-" '{for (i=1;i<=NF-2;i++)printf("%s-", $i);printf("%s", $(NF-1));printf("@%s", $NF);print "";}' \
   | command awk -F "@" '{printf("   %-20s", $1);print $2;}' \
   )"

  if [ -z "${VERSIONS}" ]; then
    fvm_echo 'N/A'
    return 3
  fi
  # the `sed` is to remove trailing whitespaces (see "weird behavior" ~25 lines up)
  fvm_echo "${VERSIONS}" | command sed 's/ *$//g'
  return $FVM_LS_REMOTE_EXIT_CODE
}

fvm_ls() {
  local PATTERN
  PATTERN="${1-}"
  local VERSIONS
  VERSIONS=''
  if [ "${PATTERN}" = 'current' ]; then
    fvm_current
    return
  fi
  if [ "${PATTERN}" = 'N/A' ]; then
    return
  fi
  # If it looks like an explicit version, don't do anything funny

  fvm_is_zsh && setopt local_options shwordsplit
  fvm_is_zsh && unsetopt local_options markdirs

  local FVM_ADD_SYSTEM
  FVM_ADD_SYSTEM=false
  if fvm_has_system_flutter; then
    FVM_ADD_SYSTEM=true
  fi

  if [ -z "${PATTERN}" ]; then
    PATTERN=''
  fi
  local SEARCH_DIR
  SEARCH_DIR="${FVM_DIR}/versions"
  if [ -n "${SEARCH_DIR}" ]; then
    VERSIONS="$(command find "${SEARCH_DIR}"/* -type d -prune -name "${PATTERN}*" \
      | command sed -e "
          s#^${FVM_DIR}/##;
          \\#^versions\$# d;
          s#^versions/##;
        " \
        -e 's#^\([^/]\{1,\}\)/\(.*\)$#\2.\1#;' \
      | command sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n \
    )"
  fi

  if [ "${FVM_ADD_SYSTEM-}" = true ]; then
    if [ -z "${PATTERN}" ] || [ "${PATTERN}" = '*' ]; then
      VERSIONS="${VERSIONS}$(command printf '\n%s' 'system')"
    elif [ "${PATTERN}" = 'system' ]; then
      VERSIONS="$(command printf '%s' 'system')"
    fi
  fi

  if [ -z "${VERSIONS}" ]; then
    fvm_echo 'N/A'
    return 3
  fi

  fvm_echo "${VERSIONS}"
}

fvm_releases() {
  local FVM_OS
  FVM_OS="$(fvm_get_os)"
  if [ "_${FVM_OS}" = "_unsupported" ]; then
    fvm_err "Currently there is no support for this os with flutter."
    return 1
  fi
  local RELEASES_URL="${FLUTTER_RELEASE_BASE_URL}/releases_${FVM_OS}.json"
  local LIST="fvm_download -Ss "${RELEASES_URL}" | command grep '\"archive\":' | command grep '"${PATTERN}"'"
  eval "$LIST | awk -F '\"' '{print \$(NF-1)}'"
}

fvm_version_from_archive() {
  fvm_echo "$(fvm_echo "${1-}" \
   | fvm_grep -v "N/A" \
   | command awk -F "/" '{print $NF}' \
   | command awk -F ".zip" '{print $(NF-1)}' \
   | command awk -F "_" '{print $NF}' \
   | command sed '/^ *$/d')"
}

fvm_print_versions() {
  fvm_err "${1-}"
}

fvm_install(){
  local PROVIDED_VERSION="${1-}"
  if [[ -z ${PROVIDED_VERSION}  ]];then
    fvm_err "Error: \$version is required !!" 
    exit 1
  fi

  local VERSION
  VERSION="$(fvm_resolve_version "${PROVIDED_VERSION}")"

  local FVM_OS
  FVM_OS="$(fvm_get_os)"
  if [ "_${FVM_OS}" = "_unsupported" ]; then
    fvm_err "Flutter only supports host OS: macOS, Linux, Windows."
    return 1
  fi

  local PATTERN
  PATTERN="flutter_${FVM_OS}_${VERSION}"
  local ARCHIVE
  ARCHIVE="$(fvm_releases | grep "${PATTERN}" | awk 'NR==1')"

  VERSION="$(fvm_version_from_archive "${ARCHIVE}" \
   | command awk -F "-" '{for (i=1;i<=NF-2;i++)printf("%s-", $i);printf("%s", $(NF-1));print "";}' \
   )"

  if [ "${VERSION}" = 'N/A' ]; then
    local REMOTE_CMD
    REMOTE_CMD='fvm ls-remote'
    fvm_err "Version '${PROVIDED_VERSION}' not found - try \`${REMOTE_CMD}\` to browse available versions."
    return 3
  fi
  if [ "$VERSION" != "$PROVIDED_VERSION" ]; then
    fvm_err "Resolve version $PROVIDED_VERSION to $VERSION"
  fi

  local EXIT_CODE
  EXIT_CODE=0

  if fvm_is_version_installed "${VERSION}"; then
    fvm_err "${VERSION} is already installed."
    EXIT_CODE=$?
    return $EXIT_CODE
  fi
  if [[ -z ${ARCHIVE}  ]];then
    fvm_err "Error: no flutter version matched $VERSION !!"
    return 1
  fi
  local CACHE_DIR="$(fvm_cache_dir)"
  local ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE}"
  if fvm_is_version_installed "${VERSION}";then
    fvm_err "$VERSION is already installed."
    return
  fi
  if [ ! -f "${ARCHIVE_PATH}" ]; then
    fvm_err "$VERSION is downloading..."
    command mkdir -p `dirname $ARCHIVE_PATH`
    local ARCHIVE_URL="${FLUTTER_RELEASE_BASE_URL}/${ARCHIVE}"
    fvm_download --progress-bar -o $ARCHIVE_PATH $ARCHIVE_URL
  else
    fvm_err "$VERSION is already downloaded."
  fi
  local TMPPATH="${CACHE_DIR}/tmp"
  local VERSION_DIR="$(fvm_version_path "${VERSION}")"
  command unzip -oq $ARCHIVE_PATH -d $TMPPATH \
          && mv "${TMPPATH}/flutter" $VERSION_DIR \
          && rm -fr $TMPPATH
  fvm_err "Now $VERSION is installed"

  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ]; then
    # Currently there is no active flutter
    if [ "_none" = "_$(fvm_current)" ]; then
      fvm_use_global "${VERSION}"
    fi
    EXIT_CODE=$?
  fi
}

fvm_get_os() {
  local FVM_UNAME
  FVM_UNAME="$(command uname -a)"
  local FVM_OS
  case "${FVM_UNAME}" in
    Linux\ *) FVM_OS=linux ;;
    Darwin\ *) FVM_OS=macos ;;
    CYGWIN* | MSYS* | MINGW*) FVM_OS=windows ;;
    *) FVM_OS=unsupported ;;
  esac
  fvm_echo "${FVM_OS-}"
}

fvm_get_arch() {
  local HOST_ARCH
  local FVM_OS
  local EXIT_CODE

  FVM_OS="$(fvm_get_os)"
  HOST_ARCH="$(command uname -m)"

  local FVM_ARCH
  case "${HOST_ARCH}" in
    x86_64 | amd64) FVM_ARCH="x64" ;;
    i*86) FVM_ARCH="x86" ;;
    aarch64) FVM_ARCH="arm64" ;;
    *) FVM_ARCH="${HOST_ARCH}" ;;
  esac

  fvm_echo "${FVM_ARCH}"
}

fvm_use_global() {
  local VERSION
  VERSION="${1-}"

  local FVM_VERSION_DIR
  FVM_VERSION_DIR="$(fvm_version_path "${VERSION}")"

  # Change current version
  PATH="$(fvm_change_path "${PATH}" "/bin" "${FVM_VERSION_DIR}")"
  if fvm_has manpath; then
    if [ -z "${MANPATH-}" ]; then
      local MANPATH
      MANPATH=$(manpath)
    fi
    # Change current version
    MANPATH="$(fvm_change_path "${MANPATH}" "/share/man" "${FVM_VERSION_DIR}")"
    export MANPATH
  fi
  export PATH
  hash -r
  export FVM_BIN="${FVM_VERSION_DIR}/bin"
  if [ "${FVM_SYMLINK_CURRENT-}" = true ]; then
    command rm -f "${FVM_DIR}/current" && ln -s "${FVM_VERSION_DIR}" "${FVM_DIR}/current"
  fi
}

fvm_use_local() {

  local VERSION
  VERSION="${1-}"

  local FVM_VERSION_DIR
  FVM_VERSION_DIR="$(fvm_version_path "${VERSION}")"
  command ln -s "${FVM_VERSION_DIR}" ".flutter"
}

fvm_sanitize_path() {
  local SANITIZED_PATH
  SANITIZED_PATH="${1-}"
  if [ "_${SANITIZED_PATH}" != "_${FVM_DIR}" ]; then
    SANITIZED_PATH="$(fvm_echo "${SANITIZED_PATH}" | command sed -e "s#${FVM_DIR}#\${FVM_DIR}#g")"
  fi
  if [ "_${SANITIZED_PATH}" != "_${HOME}" ]; then
    SANITIZED_PATH="$(fvm_echo "${SANITIZED_PATH}" | command sed -e "s#${HOME}#\${HOME}#g")"
  fi
  fvm_echo "${SANITIZED_PATH}"
}

fvm_strip_path() {
  if [ -z "${FVM_DIR-}" ]; then
    fvm_err '${FVM_DIR} not set!'
    return 1
  fi
  command printf %s "${1-}" | command awk -v FVM_DIR="${FVM_DIR}" -v RS=: '
  index($0, FVM_DIR) == 1 {
    path = substr($0, length(FVM_DIR) + 1)
    if (path ~ "^(/versions/[^/]*)?/versions/[^/]*'"${2-}"'.*$") { next }
  }
  { print }' | command paste -s -d: -
}

fvm_change_path() {
  # if there’s no initial path, just return the supplementary path
  if [ -z "${1-}" ]; then
    fvm_echo "${3-}${2-}"
  # if the initial path doesn’t contain an fvm path, prepend the supplementary
  # path
  elif ! fvm_echo "${1-}" | fvm_grep -q "${FVM_DIR}/versions/[^/]*${2-}" \
    && ! fvm_echo "${1-}" | fvm_grep -q "${FVM_DIR}/versions/[^/]*/[^/]*${2-}"; then
    fvm_echo "${3-}${2-}:${1-}"
  # if the initial path contains BOTH an fvm path (checked for above) and
  # that fvm path is preceded by a system binary path, just prepend the
  # supplementary path instead of replacing it.
  # https://github.com/nvm-sh/nvm/issues/1652#issuecomment-342571223
  elif fvm_echo "${1-}" | fvm_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${FVM_DIR}/versions/[^/]*${2-}" \
    || fvm_echo "${1-}" | fvm_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${FVM_DIR}/versions/[^/]*/[^/]*${2-}"; then
    fvm_echo "${3-}${2-}:${1-}"
  # use sed to replace the existing fvm path with the supplementary path. This
  # preserves the order of the path.
  else
    fvm_echo "${1-}" | command sed \
      -e "s#${FVM_DIR}/versions/[^/]*${2-}[^:]*#${3-}${2-}#" \
      -e "s#${FVM_DIR}/versions/[^/]*/[^/]*${2-}[^:]*#${3-}${2-}#"
  fi
}

fvm_cache_dir() {
  fvm_echo "${FVM_DIR}/.cache"
}

fvm() {
  if [ "$#" -lt 1 ]; then
    fvm --help
    return
  fi

  local DEFAULT_IFS
  DEFAULT_IFS=" $(fvm_echo t | command tr t \\t)
"
  if [ "${-#*e}" != "$-" ]; then
    set +e
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" fvm "$@"
    EXIT_CODE="$?"
    set -e
    return "$EXIT_CODE"
  elif [ "${-#*a}" != "$-" ]; then
    set +a
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" fvm "$@"
    EXIT_CODE="$?"
    set -a
    return "$EXIT_CODE"
  elif [ -n "${BASH-}" ] && [ "${-#*E}" != "$-" ]; then
    # shellcheck disable=SC3041
    set +E
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" fvm "$@"
    EXIT_CODE="$?"
    # shellcheck disable=SC3041
    set -E
    return "$EXIT_CODE"
  elif [ "${IFS}" != "${DEFAULT_IFS}" ]; then
    IFS="${DEFAULT_IFS}" fvm "$@"
    return "$?"
  fi

  local i
  for i in "$@"
  do
    case $i in
      --) break ;;
      '-h'|'help'|'--help')
        FVM_VERSION="$(fvm --version)"
        fvm_echo
        fvm_echo "Flutter Version Manager (v${FVM_VERSION})"
        fvm_echo
        fvm_echo 'Note: <version> refers to any version string fvm understands.'
        fvm_echo
        fvm_echo 'Usage:'
        fvm_echo '  fvm --help                                  Show this message'
        fvm_echo '  fvm --version                               Print out the installed version of fvm'
        fvm_echo '  fvm install [<version>]                     Download and install a <version>. Uses flutter.version if available and version is omitted.'
        fvm_echo '  fvm uninstall <version>                     Uninstall a version'
        fvm_echo '  fvm use [<version>]                         Modify PATH to use <version>. Uses flutter.version if available and version is omitted.'
        fvm_echo '   The following optional arguments, if provided, must appear directly after `fvm use`:'
        fvm_echo '    --silent                                  Silences stdout/stderr output'
        fvm_echo '  fvm current                                 Display currently activated version of Flutter'
        fvm_echo '  fvm ls [<version>]                          List installed versions, matching a given <version> if provided'
        fvm_echo '  fvm ls-remote [<version>]                   List remote versions available for install, matching a given <version> if provided'
        fvm_echo '  fvm deactivate                              Undo effects of `fvm` on current shell'
        fvm_echo '    --silent                                  Silences stdout/stderr output'
        fvm_echo '  fvm unload                                  Unload `fvm` from shell'
        fvm_echo '  fvm which [current | <version>]             Display path to installed flutter version. Uses flutter.version if available and version is omitted.'
        fvm_echo '    --silent                                  Silences stdout/stderr output when a version is omitted'
        fvm_echo 'Example:'
        fvm_echo '  fvm install 2.0.0                     Install a specific version number'
        fvm_echo '  fvm use 2.0.0                         Use 2.0.0 release'
        fvm_echo
        fvm_echo 'Note:'
        fvm_echo '  to remove, delete, or uninstall fvm - just remove the `$FVM_DIR` folder (usually `~/.fvm`)'
        fvm_echo
        return 0;
      ;;
    esac
  done

  local COMMAND
  COMMAND="${1-}"
  shift

  # initialize local variables
  local VERSION

  case $COMMAND in
    "debug")
      local OS_VERSION
      fvm_is_zsh && setopt local_options shwordsplit
      fvm_err "fvm --version: v$(fvm --version)"
      if [ -n "${TERM_PROGRAM-}" ]; then
        fvm_err "\$TERM_PROGRAM: ${TERM_PROGRAM}"
      fi
      fvm_err "\$SHELL: ${SHELL}"
      # shellcheck disable=SC2169,SC3028
      fvm_err "\$SHLVL: ${SHLVL-}"
      fvm_err "whoami: '$(whoami)'"
      fvm_err "\${HOME}: ${HOME}"
      fvm_err "\${FVM_DIR}: '$(fvm_sanitize_path "${FVM_DIR}")'"
      fvm_err "\${PATH}: $(fvm_sanitize_path "${PATH}")"
      fvm_err "\$PREFIX: '$(fvm_sanitize_path "${PREFIX}")'"
      fvm_err "shell version: '$(${SHELL} --version | command head -n 1)'"
      fvm_err "uname -a: '$(command uname -a | command awk '{$2=""; print}' | command xargs)'"
      if [ "$(fvm_get_os)" = "macos" ] && fvm_has sw_vers; then
        OS_VERSION="$(sw_vers | command awk '{print $2}' | command xargs)"
      elif [ -r "/etc/issue" ]; then
        OS_VERSION="$(command head -n 1 /etc/issue | command sed 's/\\.//g')"
        if [ -z "${OS_VERSION}" ] && [ -r "/etc/os-release" ]; then
          # shellcheck disable=SC1091
          OS_VERSION="$(. /etc/os-release && echo "${NAME}" "${VERSION}")"
        fi
      fi
      if [ -n "${OS_VERSION}" ]; then
        fvm_err "OS version: ${OS_VERSION}"
      fi
      if fvm_has "awk"; then
        fvm_err "awk: $(fvm_command_info awk), $({ command awk --version 2>/dev/null || command awk -W version; } \
          | command head -n 1)"
      else
        fvm_err "awk: not found"
      fi
      if fvm_has "curl"; then
        fvm_err "curl: $(fvm_command_info curl), $(command curl -V | command head -n 1)"
      else
        fvm_err "curl: not found"
      fi
      if fvm_has "wget"; then
        fvm_err "wget: $(fvm_command_info wget), $(command wget -V | command head -n 1)"
      else
        fvm_err "wget: not found"
      fi

      local TEST_TOOLS ADD_TEST_TOOLS
      TEST_TOOLS="git grep"
      ADD_TEST_TOOLS="sed cut basename rm mkdir xargs"
      if [ "macos" != "$(fvm_get_os)" ]; then
        TEST_TOOLS="${TEST_TOOLS} ${ADD_TEST_TOOLS}"
      else
        for tool in ${ADD_TEST_TOOLS} ; do
          if fvm_has "${tool}"; then
            fvm_err "${tool}: $(fvm_command_info "${tool}")"
          else
            fvm_err "${tool}: not found"
          fi
        done
      fi
      for tool in ${TEST_TOOLS} ; do
        local FVM_TOOL_VERSION
        if fvm_has "${tool}"; then
          if command ls -l "$(fvm_command_info "${tool}" | command awk '{print $1}')" | command grep -q busybox; then
            FVM_TOOL_VERSION="$(command "${tool}" --help 2>&1 | command head -n 1)"
          else
            FVM_TOOL_VERSION="$(command "${tool}" --version 2>&1 | command head -n 1)"
          fi
          fvm_err "${tool}: $(fvm_command_info "${tool}"), ${FVM_TOOL_VERSION}"
        else
          fvm_err "${tool}: not found"
        fi
        unset FVM_TOOL_VERSION
      done
      unset TEST_TOOLS ADD_TEST_TOOLS

      local FVM_DEBUG_OUTPUT
      for FVM_DEBUG_COMMAND in 'fvm current' 'which flutter' 'which dart'; do
        FVM_DEBUG_OUTPUT="$(${FVM_DEBUG_COMMAND} 2>&1)"
        fvm_err "${FVM_DEBUG_COMMAND}: $(fvm_sanitize_path "${FVM_DEBUG_OUTPUT}")"
      done
      return 42
    ;;

    "install" | "i")

      if ! fvm_has "curl" && ! fvm_has "wget"; then
        fvm_err 'fvm needs curl or wget to proceed.'
        return 1
      fi

      while [ $# -ne 0 ]; do
        case "$1" in
          ---*)
            fvm_err 'arguments with `---` are not supported - this is likely a typo'
            return 55;
          ;;
          *)
            break # stop parsing args
          ;;
        esac
      done

      local PROVIDED_VERSION
      PROVIDED_VERSION="${1-}"

      if [ -z "${PROVIDED_VERSION}" ]; then
        fvm_flutter_version
        if [ -z "${FVM_FLUTTER_VERSION}" ]; then
          unset FVM_FLUTTER_VERSION
          >&2 fvm --help
          return 127
        fi
        PROVIDED_VERSION="${FVM_FLUTTER_VERSION}"
        unset FVM_FLUTTER_VERSION
      elif [ $# -gt 0 ]; then
        shift
      fi

      local EXIT_CODE
      EXIT_CODE=0

      fvm_install "${PROVIDED_VERSION}"
      EXIT_CODE=$?
      return $EXIT_CODE
    ;;
    "uninstall")
      if [ $# -ne 1 ]; then
        >&2 fvm --help
        return 127
      fi

      local PROVIDED_VERSION
      PROVIDED_VERSION="${1-}"
      local VERSION="$(fvm_resolve_version "${PROVIDED_VERSION}")"

      if [ "_${VERSION}" = "_system" ]; then
        fvm_err "fvm: Cannot uninstall system flutter version."
        return 1
      fi

      if [ "_${VERSION}" = "_$(fvm_current)" ]; then
        fvm_err "fvm: Cannot uninstall currently-active flutter version, ${VERSION} (inferred from ${PROVIDED_VERSION})."
        return 1
      fi

      if ! fvm_is_version_installed "${VERSION}"; then
        fvm_err "${VERSION} version is not installed yet."
        return
      fi

      local VERSION_PATH
      VERSION_PATH="$(fvm_version_path "${VERSION}")"

      # Delete all files related to target version.
      command rm -rf \
        "${VERSION_PATH}" 2>/dev/null
      fvm_echo "Uninstalled flutter ${VERSION}"
    ;;
    "deactivate")
      local FVM_SILENT
      while [ $# -ne 0 ]; do
        case "${1}" in
          --silent) FVM_SILENT=1 ;;
          --) ;;
        esac
        shift
      done
      local NEWPATH
      NEWPATH="$(fvm_strip_path "${PATH}" "/bin")"
      if [ "_${PATH}" = "_${NEWPATH}" ]; then
        if [ "${FVM_SILENT:-0}" -ne 1 ]; then
          fvm_err "Could not find ${FVM_DIR}/*/bin in \${PATH}"
        fi
      else
        export PATH="${NEWPATH}"
        hash -r
        if [ "${FVM_SILENT:-0}" -ne 1 ]; then
          fvm_echo "${FVM_DIR}/*/bin removed from \${PATH}"
        fi
      fi

      if [ -n "${MANPATH-}" ]; then
        NEWPATH="$(fvm_strip_path "${MANPATH}" "/share/man")"
        if [ "_${MANPATH}" = "_${NEWPATH}" ]; then
          if [ "${FVM_SILENT:-0}" -ne 1 ]; then
            fvm_err "Could not find ${FVM_DIR}/*/share/man in \${MANPATH}"
          fi
        else
          export MANPATH="${NEWPATH}"
          if [ "${FVM_SILENT:-0}" -ne 1 ]; then
            fvm_echo "${FVM_DIR}/*/share/man removed from \${MANPATH}"
          fi
        fi
      fi
      unset FVM_BIN
    ;;
    "use")
      local PROVIDED_VERSION
      local FVM_SILENT
      local FVM_SILENT_ARG
      local IS_VERSION_FROM_FLUTTER_VERSION_FILE
      IS_VERSION_FROM_FLUTTER_VERSION_FILE=0

      while [ $# -ne 0 ]; do
        case "$1" in
          --silent)
            FVM_SILENT=1
            FVM_SILENT_ARG='--silent'
          ;;
          *)
            if [ -n "${1-}" ]; then
              PROVIDED_VERSION="$1"
            fi
          ;;
        esac
        shift
      done

      if [ -z "${PROVIDED_VERSION-}" ]; then
        FVM_SILENT="${FVM_SILENT:-0}" fvm_flutter_version
        if [ -n "${FVM_FLUTTER_VERSION-}" ]; then
          PROVIDED_VERSION="${FVM_FLUTTER_VERSION}"
          IS_VERSION_FROM_FLUTTER_VERSION_FILE=1
        fi
        unset FVM_FLUTTER_VERSION
        if [ -z "${PROVIDED_VERSION}" ]; then
          fvm_err 'Please see `fvm --help` or https://github.com/fvm-sh/fvm#flutterversion for more information.'
          return 127
        fi
      fi

      if [ -z "${PROVIDED_VERSION}" ]; then
        >&2 fvm --help
        return 127
      fi
      local VERSION="$(fvm_resolve_version "${PROVIDED_VERSION}")"

      if [ "_${VERSION}" = '_system' ]; then
        if fvm_has_system_flutter && fvm deactivate "${FVM_SILENT_ARG-}" >/dev/null 2>&1; then
          if [ "${FVM_SILENT:-0}" -ne 1 ]; then
            fvm_echo "Now using system installed flutter."
          fi
          return
        elif [ "${FVM_SILENT:-0}" -ne 1 ]; then
          fvm_err 'System version of flutter not found.'
        fi
        return 127
      fi
      if [ "${VERSION}" = 'N/A' ]; then
        if [ "${FVM_SILENT:-0}" -ne 1 ]; then
          fvm_ensure_version_installed "${PROVIDED_VERSION}" "${IS_VERSION_FROM_FLUTTER_VERSION_FILE}"
        fi
        return 3
      # This fvm_ensure_version_installed call can be a performance bottleneck
      # on shell startup. Perhaps we can optimize it away or make it faster.
      elif ! fvm_ensure_version_installed "${VERSION}" "${IS_VERSION_FROM_FLUTTER_VERSION_FILE}"; then
        return $?
      fi
      fvm_use_global "${VERSION}" "${IS_VERSION_FROM_FLUTTER_VERSION_FILE}"
      local FVM_USE_OUTPUT
      FVM_USE_OUTPUT=''
      if [ "${FVM_SILENT:-0}" -ne 1 ]; then
        FVM_USE_OUTPUT="Now using flutter ${VERSION}"
      fi
      if [ -n "${FVM_USE_OUTPUT-}" ] && [ "${FVM_SILENT:-0}" -ne 1 ]; then
        fvm_echo "${FVM_USE_OUTPUT}"
      fi
    ;;
    "ls" | "list")
      local PATTERN

      while [ $# -gt 0 ]; do
        case "${1}" in
          --) ;;
          --*)
            fvm_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            PATTERN="${PATTERN:-$1}"
          ;;
        esac
        shift
      done
      local FVM_LS_OUTPUT
      local FVM_LS_EXIT_CODE
      FVM_LS_OUTPUT=$(fvm_ls "${PATTERN-}")
      FVM_LS_EXIT_CODE=$?
      fvm_print_versions "${FVM_LS_OUTPUT}"
      return $FVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote")

      local FVM_OUTPUT
      local EXIT_CODE
      FVM_OUTPUT="$(fvm_ls_remote "$@")"
      EXIT_CODE=$?
      if [ -n "${FVM_OUTPUT}" ]; then
        fvm_print_versions "${FVM_OUTPUT}"
        return $EXIT_CODE
      fi
      fvm_print_versions "N/A"
      return 3
    ;;
    "current")
      fvm_resolve_version current
    ;;
    "which")
      local FVM_SILENT
      local PROVIDED_VERSION
      while [ $# -ne 0 ]; do
        case "${1}" in
          --silent) FVM_SILENT=1 ;;
          --) ;;
          *) PROVIDED_VERSION="${1-}" ;;
        esac
        shift
      done
      if [ -z "${PROVIDED_VERSION-}" ]; then
        FVM_SILENT="${FVM_SILENT:-0}" fvm_flutter_version
        if [ -n "${FVM_FLUTTER_VERSION}" ]; then
          PROVIDED_VERSION="${FVM_FLUTTER_VERSION}"
        fi
        unset FVM_FLUTTER_VERSION
      fi
      if [ -z "${PROVIDED_VERSION}" ]; then
        >&2 fvm --help
        return 127
      fi
      local VERSION="$(fvm_resolve_version "${PROVIDED_VERSION}")"

      if [ "_${VERSION}" = '_system' ]; then
        if fvm_has_system_flutter >/dev/null 2>&1; then
          local FVM_BIN
          FVM_BIN="$(fvm use system >/dev/null 2>&1 && command which flutter)"
          if [ -n "${FVM_BIN}" ]; then
            fvm_echo "${FVM_BIN}"
            return
          fi
          return 1
        fi
        fvm_err 'System version of flutter not found.'
        return 127
      fi

      fvm_ensure_version_installed "${PROVIDED_VERSION}"
      EXIT_CODE=$?
      if [ "${EXIT_CODE}" != "0" ]; then
        return $EXIT_CODE
      fi
      local FVM_VERSION_DIR
      FVM_VERSION_DIR="$(fvm_version_path "${VERSION}")"
      fvm_echo "${FVM_VERSION_DIR}/bin/flutter"
    ;;
    "--version" | "-v")
      fvm_echo '0.0.1'
    ;;
    "unload")
      fvm deactivate >/dev/null 2>&1
      unset -f fvm \
        fvm_releases fvm_current\
        fvm_ls fvm_ls_remote \
        fvm_use_global fvm_use_local \
        fvm_print_versions fvm_version_from_archive \
        fvm_resolve_version fvm_flutter_version \
        fvm_get_os fvm_get_arch \
        fvm_change_path fvm_strip_path \
        fvm_ensure_version_installed fvm_cache_dir \
        fvm_version_path \
        fvm_find_up fvm_tree_contains_path \
        fvm_version_greater_than_or_equal_to \
        fvm_has_system_flutter \
        fvm_download fvm_has \
        fvm_curl_use_compression fvm_curl_version \
        fvm_auto \
        fvm_echo fvm_err fvm_grep fvm_cd \
        fvm_is_version_installed \
        fvm_sanitize_path fvm_process_parameters \
        fvm_curl_libz_support fvm_command_info fvm_is_zsh fvm_stdout_is_terminal \
        >/dev/null 2>&1
      unset FVM_FLUTTER_VERSION FVM_DIR \
        FVM_CD_FLAGS FVM_BIN \
        >/dev/null 2>&1
    ;;
    *)
      >&2 fvm --help
      return 127
    ;;
  esac
}

fvm_auto() {
  local FVM_MODE
  FVM_MODE="${1-}"
  local FVM_CURRENT
  if [ "_${FVM_MODE}" = '_install' ]; then
    if fvm_flutter_version >/dev/null 2>&1; then
      fvm install >/dev/null
    fi
  elif [ "_$FVM_MODE" = '_use' ]; then
    FVM_CURRENT="$(fvm_current)"
    if [ "_${FVM_CURRENT}" = '_none' ] || [ "_${FVM_CURRENT}" = '_system' ]; then
      if fvm_flutter_version >/dev/null 2>&1; then
        fvm use --silent >/dev/null
      fi
    else
      fvm use --silent "${FVM_CURRENT}" >/dev/null
    fi
  elif [ "_${FVM_MODE}" != '_none' ]; then
    fvm_err 'Invalid auto mode supplied.'
    return 1
  fi
}

fvm_process_parameters() {
  local FVM_AUTO_MODE
  FVM_AUTO_MODE='use'
  while [ "$#" -ne 0 ]; do
    case "$1" in
      --install) FVM_AUTO_MODE='install' ;;
      --no-use) FVM_AUTO_MODE='none' ;;
    esac
    shift
  done
  fvm_auto "${FVM_AUTO_MODE}"
}

# Make zsh glob matching behave same as bash
# This fixes the "zsh: no matches found" errors
if [ -z "${FVM_CD_FLAGS-}" ]; then
  export FVM_CD_FLAGS=''
fi
if fvm_is_zsh; then
  FVM_CD_FLAGS="-q"
fi

# Auto detect the FVM_DIR when not set
if [ -z "${FVM_DIR-}" ]; then
  # shellcheck disable=SC2128
  if [ -n "${BASH_SOURCE-}" ]; then
    # shellcheck disable=SC2169,SC3054
    FVM_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  FVM_DIR="$(fvm_cd ${FVM_CD_FLAGS} "$(dirname "${FVM_SCRIPT_SOURCE:-$0}")" >/dev/null && \pwd)"
  export FVM_DIR
else
  # https://unix.stackexchange.com/a/198289
  case $FVM_DIR in
    *[!/]*/)
      FVM_DIR="${FVM_DIR%"${FVM_DIR##*[!/]}"}"
      export FVM_DIR
      fvm_err "Warning: \$FVM_DIR should not have trailing slashes"
    ;;
  esac
fi
unset FVM_SCRIPT_SOURCE 2>/dev/null

fvm_process_parameters "$@"

} # this ensures the entire script is downloaded #
