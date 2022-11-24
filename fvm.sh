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

fvm_is_zsh() {
  [ -n "${ZSH_VERSION-}" ]
}

fvm_cd() {

  # Make zsh glob matching behave same as bash
  # This fixes the "zsh: no matches found" errors
  local FVM_CD_FLAGS
  if fvm_is_zsh; then
    FVM_CD_FLAGS="-q"
  fi

  \cd ${FVM_CD_FLAGS} "$@"
}

fvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
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

fvm_curl_libz_support() {
  curl -V 2>/dev/null | fvm_grep "^Features:" | fvm_grep -q "libz"
}

fvm_curl_use_compression() {
  local curl_version="$(curl -V \
    | command awk '{ if ($1 == "curl") print $2 }' \
    | command sed 's/-.*$//g'
  )"
  fvm_curl_libz_support && fvm_version_greater_than_or_equal_to "${curl_version}" 7.21.0
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

fvm_is_version_installed() {
  local VERSION="${1-}"
  if [ -z "${VERSION}" ]; then
    return 1
  fi
  if [ -x "$(fvm_version_path "${VERSION}" 2>/dev/null)/bin/flutter" ]; then
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

# exclude fvm flutter from $PATH
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

# include fvm flutter to $PATH
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

# Traverse up in directory tree to find containing folder
fvm_find_up() {
  local path_
  path_="${1-}"
  while [ "${path_}" != "" ] && [ ! -f "${path_}/${2-}" ]; do
    path_=${path_%/*}
  done
  fvm_echo "${path_}/${2-}"
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
  HOST_ARCH="$(command uname -m)"

  local FVM_ARCH
  case "${HOST_ARCH}" in
    x86_64) FVM_ARCH="x64" ;;
    i*86) FVM_ARCH="x86" ;;
    aarch64 | amd64) FVM_ARCH="arm64" ;;
    *) FVM_ARCH="${HOST_ARCH}" ;;
  esac

  fvm_echo "${FVM_ARCH}"
}

fvm_cache_dir() {
  fvm_echo "${FVM_DIR}/.cache"
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

fvm_releases() {
  local NO_STABLE
  local NO_BETA
  local NO_DEV
  local PATTERN
  while [ $# -ne 0 ]; do
    case "${1}" in
      --no-stable) NO_STABLE=1 ;;
      --no-beta) NO_BETA ;;
      --no-dev) NO_DEV=1 ;;
      --) ;;
      *) PATTERN="${1-}" ;;
    esac
    shift
  done
  local FVM_OS="$(fvm_get_os)"
  local FVM_ARCH="$(fvm_get_arch)"
  if [ "_${FVM_OS}" = "_unsupported" ]; then
    fvm_err "Currently there is no support for this os with flutter."
    return 1
  fi
  local STORAGE_BASE="${FLUTTER_STORAGE_BASE_URL:-"https://storage.googleapis.com"}"
  local RELEASES_URL="${STORAGE_BASE}/flutter_infra_release/releases/releases_${FVM_OS}.json"
  local RELEASES="$(fvm_download -Ss "${RELEASES_URL}" \
    | fvm_grep '\"archive\":' \
    | fvm_grep "_${PATTERN}" \
    | command awk -F '"' '{print $(NF-1)}' \
  )"
  if [ "_${FVM_OS}" = "_macos" ] && [ "_${FVM_ARCH}" = "_arm64" ]; then
    RELEASES="$(fvm_echo $RELEASES | fvm_grep "arm64")"
  else
    RELEASES="$(fvm_echo $RELEASES | fvm_grep -v "arm64")"
  fi
  if [ "${NO_STABLE}" = "1" ]; then
    RELEASES="$(fvm_echo "${RELEASES}" | fvm_grep -v "stable")"
  fi
  if [ "${NO_BETA}" = "1" ]; then
    RELEASES="$(fvm_echo "${RELEASES}" | fvm_grep -v "beta")"
  fi
  if [ "${NO_DEV}" = "1" ]; then
    RELEASES="$(fvm_echo "${RELEASES}" | fvm_grep -v "dev")"
  fi
  fvm_echo "${RELEASES}"
}

fvm_ls_remote() {

  local FVM_LS_REMOTE_EXIT_CODE
  FVM_LS_REMOTE_EXIT_CODE=0
  
  local FVM_LS_REMOTE_OUTPUT
  FVM_LS_REMOTE_OUTPUT="$(fvm_releases "$@" \
    | command awk -F '_' '{print $NF}' \
    | command awk -F '.zip' '{print $(NF-1)}' \
  )"

  if [ -z "${FVM_LS_REMOTE_OUTPUT}" ]; then
    fvm_echo 'N/A'
    return 3
  fi
  # the `sed` is to remove trailing whitespaces (see "weird behavior" ~25 lines up)
  fvm_echo "${FVM_LS_REMOTE_OUTPUT}" \
    | command awk -F '_' '{print $NF}' \
    | command awk -F "-" '{for (i=1;i<=NF-2;i++)printf("%s-", $i);printf("%s", $(NF-1));print "";}' \
    | command sed 's/ *$//g'
  return $FVM_LS_REMOTE_EXIT_CODE
}

fvm_ls() {
  local PATTERN
  while [ $# -ne 0 ]; do
    case "${1}" in
      --) ;;
      --*)
        fvm_err "Unsupported option \"${1}\"."
        return 55
      ;;
      *) PATTERN="${1-}" ;;
    esac
    shift
  done

  if [ -z "${PATTERN}" ]; then
    PATTERN=''
  fi
  local SEARCH_DIR
  SEARCH_DIR="${FVM_DIR}/versions"
  if [ -n "${SEARCH_DIR}" ]; then
    VERSIONS="$(command find "${SEARCH_DIR}"/* -type d -depth 0 -name "${PATTERN}*" \
      | command sed -e "
          s#^${FVM_DIR}/##;
          \\#^versions\$# d;
          s#^versions/##;
        " \
        -e 's#^\([^/]\{1,\}\)/\(.*\)$#\2.\1#;' \
      | command sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n \
    )"
  fi

  if [ -n "${VERSIONS}" ]; then
    fvm_echo "${VERSIONS}"
  fi
}

fvm_ls_current() {
  local FVM_CURRENT_FLUTTER_PATH
  FVM_CURRENT_FLUTTER_PATH="$(command which flutter 2>/dev/null)"
  if [ -n "$FVM_CURRENT_FLUTTER_PATH" ] && fvm_tree_contains_path "${FVM_DIR}" "${FVM_CURRENT_FLUTTER_PATH}"; then
    fvm_echo "${FVM_CURRENT_FLUTTER_PATH}" | command awk -F '/' '{print $(NF-2)}'
  fi
}

fvm_ls_system() {
  local FVM_SYSTEM_FLUTTER
  FVM_SYSTEM_FLUTTER="$(fvm deactivate >/dev/null 2>&1 && command which flutter)"
  if [ -n "${FVM_SYSTEM_FLUTTER}" ]; then
    local VERSION_FILE="$(fvm_find_up "${FVM_SYSTEM_FLUTTER}", "version")"
    local VERSION="$(command head -n 1 "${VERSION_FILE}" | command tr -d '\r')" || command printf ''
    if [ -n "${VERSION}" ]; then
      fvm_echo "${VERSION}"
    fi
  fi
}

fvm_ls_global() {
  if [ -f "${FVM_DIR}/flutter.version" ]; then
    local VERSION="$(command head -n 1 "${FVM_DIR}/flutter.version")"
    if [ -n "${VERSION}" ]; then
      fvm_echo "${VERSION}"
    fi
  fi
}

fvm_install(){
  local PROVIDED_VERSION
  PROVIDED_VERSION="${1-}"

  if [ -z "${PROVIDED_VERSION}" ];then
    fvm_err "fvm: version is required !!" 
    return 1
  fi

  if fvm_is_version_installed "${PROVIDED_VERSION}"; then
    fvm_err "fvm: version '${PROVIDED_VERSION}' is already installed."
    return 1
  fi

  local ARCHIVE
  ARCHIVE="$(fvm_releases "${PROVIDED_VERSION}" | command awk 'NR==1')"

  local VERSION
  VERSION="$(fvm_echo "${ARCHIVE}" \
    | command awk -F '_' '{print $NF}' \
    | command awk -F "-" '{for (i=1;i<=NF-2;i++)printf("%s-", $i);printf("%s", $(NF-1));print "";}' \
  )"

  if [ -z "${VERSION}" ]; then
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
    fvm_err "fvm: no flutter version matched $VERSION !!"
    return 1
  fi
  local CACHE_DIR="$(fvm_cache_dir)"
  local ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE}"
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
  return EXIT_CODE
}

fvm_use_global() {
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
        fvm_echo "Flutter Version Manager (${FVM_VERSION})"
        fvm_echo
        fvm_echo 'Note: <version> refers to any version string fvm understands.'
        fvm_echo
        fvm_echo 'Usage:'
        fvm_echo '  fvm --help                                  Show this message'
        fvm_echo '  fvm --version                               Print out the installed version of fvm'
        fvm_echo '  fvm install [<version>]                     Download and install a <version>.'
        fvm_echo '  fvm uninstall <version>                     Uninstall a version'
        fvm_echo '  fvm use [<version>]                         Modify PATH to use flutter <version>.'
        fvm_echo '   The following optional arguments:'
        fvm_echo '    -g,--global                               Modify global default flutter <version>.'
        fvm_echo '  fvm current                                 Display currently activated version of Flutter'
        fvm_echo '  fvm ls [<version>]                          List installed versions, matching a given <version> if provided'
        fvm_echo '  fvm ls-remote [<version>]                   List remote versions available for install, matching a given <version> if provided'
        fvm_echo '   The following optional arguments:'
        fvm_echo '    --no-stable                               Exclude stable released versions'
        fvm_echo '    --no-beta                                 Exclude beta released versions'
        fvm_echo '    --no-dev                                  Exclude dev released versions'
        fvm_echo '  fvm deactivate                              Undo effects of `fvm` on current shell'
        fvm_echo '    --silent                                  Silences stdout/stderr output'
        fvm_echo '  fvm unload                                  Unload `fvm` from shell'
        fvm_echo 'Example:'
        fvm_echo '  fvm install 3.0                       Install the lastest 3.0.x version of flutter'
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
    "install" | "i")

      if ! fvm_has "curl" && ! fvm_has "wget"; then
        fvm_err 'fvm needs curl or wget to proceed.'
        return 1
      fi

      local EXIT_CODE
      EXIT_CODE=0
      fvm_install "$@"
      EXIT_CODE=$?
      return $EXIT_CODE
    ;;
    "uninstall")

      local PROVIDED_VERSION
      PROVIDED_VERSION="${1-}"

      if [[ -z ${PROVIDED_VERSION}  ]];then
        fvm_err "fvm: version is required !!" 
        return 1
      fi
      local global_version
      global_version="$(fvm_ls_global)"
      if [ "${PROVIDED_VERSION}" = "${global_version}" ]; then
        fvm_err "fvm: Cannot uninstall global-active flutter version ${global_version}."
        return 1
      fi

      if ! fvm_is_version_installed "${PROVIDED_VERSION}"; then
        fvm_err "${PROVIDED_VERSION} version is not installed yet."
        return 1
      fi

      local VERSION_PATH
      VERSION_PATH="$(fvm_version_path "${PROVIDED_VERSION}")"

      # Delete all files related to target version.
      command rm -rf \
        "${VERSION_PATH}" 2>/dev/null
      fvm_echo "Uninstalled flutter ${PROVIDED_VERSION}"
    ;;
    "use")
      local PROVIDED_VERSION
      local FVM_USE_GLOBAL

      while [ $# -ne 0 ]; do
        case "$1" in
          -g | --global)
            FVM_USE_GLOBAL=1
          ;;
          *)
            if [ -n "${1-}" ]; then
              PROVIDED_VERSION="$1"
            fi
          ;;
        esac
        shift
      done

      if [ -z "${PROVIDED_VERSION}" ]; then
        >&2 fvm --help
        return 127
      fi
      if [ "_${PROVIDED_VERSION}" = '_system' ]; then
        local FVM_SYSTEM_VERSION="$(fvm_ls_system)"
        if [ -n "${FVM_SYSTEM_VERSION}" ] && fvm deactivate >/dev/null 2>&1; then
          fvm_echo "Now using system version of flutter: ${FVM_SYSTEM_VERSION}"
          return
        else
          fvm_err 'System version of flutter not found.'
        fi
        return 127
      fi

      if ! fvm_is_version_installed "${PROVIDED_VERSION}"; then
        fvm_err "fvm: version \"${PROVIDED_VERSION}\" is not yet installed."
        fvm_err ""
        fvm_err "You need to run \`fvm install ${PROVIDED_VERSION}\` to install and use it."
        return 1
      fi

      local FVM_VERSION_DIR
      FVM_VERSION_DIR="$(fvm_version_path "${PROVIDED_VERSION}")"

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
      fvm_echo "Now using flutter ${PROVIDED_VERSION}"
      if [ "${FVM_USE_GLOBAL}" = "1" ]; then
        fvm_echo "${PROVIDED_VERSION}" > "${FVM_DIR}/flutter.version"
      fi
    ;;
    "ls" | "list")
      local FVM_LS_OUTPUT
      local FVM_LS_EXIT_CODE
      FVM_LS_OUTPUT=$(fvm_ls "$@")
      if [ -n "${FVM_LS_OUTPUT}" ]; then
        fvm_echo "${FVM_LS_OUTPUT}"
      fi
      local system_version="$(fvm_ls_system)"
      if [ -n "${system_version}" ]; then
        fvm_echo "${system_version} (Manually installed)"
      fi
    ;;
    "ls-remote" | "list-remote")
      local FVM_LS_REMOTE_OUTPUT
      local FVM_LS_REMOTE_EXIT_CODE
      FVM_LS_REMOTE_OUTPUT="$(fvm_ls_remote "$@")"
      FVM_LS_REMOTE_EXIT_CODE=$?
      if [ -n "${FVM_LS_REMOTE_OUTPUT}" ]; then
        fvm_echo "${FVM_LS_REMOTE_OUTPUT}"
        return $FVM_LS_REMOTE_EXIT_CODE
      fi
      fvm_echo "N/A"
      return 3
    ;;
    "current")
      local FVM_CURRENT="$(fvm_ls_current)"
      if [ -n "${FVM_CURRENT}" ]; then
        fvm_echo "${FVM_CURRENT}"
        return
      fi
      local system_version="$(fvm_ls_system)"
      if [ -n "${system_version}" ]; then
        fvm_echo "${system_version} (Manually installed)"
      fi
    ;;
    "--version" | "-v")
      fvm_echo 'v0.0.1'
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
          fvm_err "${FVM_DIR}/*/bin removed from \${PATH}"
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
            fvm_err "${FVM_DIR}/*/share/man removed from \${MANPATH}"
          fi
        fi
      fi
    ;;
    "unload")
      fvm deactivate >/dev/null 2>&1
      unset -f fvm \
        fvm_ls_global fvm_ls_system fvm_ls_current \
        fvm_releases fvm_ls fvm_ls_remote fvm_install \
        fvm_echo fvm_err fvm_grep fvm_cd fvm_has fvm_is_zsh \
        fvm_get_os fvm_get_arch \ fvm_find_up \
        fvm_tree_contains_path fvm_strip_path fvm_change_path \
        fvm_version_greater_than_or_equal_to \
        fvm_download \
        fvm_cache_dir fvm_is_version_installed fvm_version_path \
        fvm_curl_use_compression \ fvm_curl_libz_support \
        >/dev/null 2>&1
      unset FVM_DIR \
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
  if [ "_$FVM_MODE" = '_use' ]; then
    local FVM_GLOBAL
    FVM_GLOBAL="$(fvm_ls_global)"
    if [ -n "${FVM_GLOBAL}" ]; then
      fvm use --silent "${FVM_GLOBAL}" >/dev/null
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
      --no-use) FVM_AUTO_MODE='none' ;;
    esac
    shift
  done
  fvm_auto "${FVM_AUTO_MODE}"
}

# Auto detect the FVM_DIR when not set
if [ -z "${FVM_DIR-}" ]; then
  # shellcheck disable=SC2128
  if [ -n "${BASH_SOURCE-}" ]; then
    # shellcheck disable=SC2169,SC3054
    FVM_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  FVM_DIR="$(fvm_cd "$(dirname "${FVM_SCRIPT_SOURCE:-$0}")" >/dev/null && \pwd)"
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
