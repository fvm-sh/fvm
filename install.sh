#!/usr/bin/env bash

{ # this ensures the entire script is downloaded #

fvm_has() {
  type "$1" > /dev/null 2>&1
}

fvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

if [ -z "${BASH_VERSION}" ] || [ -n "${ZSH_VERSION}" ]; then
  # shellcheck disable=SC2016
  fvm_echo >&2 'Error: the install instructions explicitly say to pipe the install script to `bash`; please follow them'
  exit 1
fi

fvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

fvm_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.fvm" || printf %s "${XDG_CONFIG_HOME}/fvm"
}

fvm_install_dir() {
  if [ -n "$FVM_DIR" ]; then
    printf %s "${FVM_DIR}"
  else
    fvm_default_install_dir
  fi
}

fvm_latest_version() {
  fvm_echo "v0.3.0"
}

fvm_profile_is_bash_or_zsh() {
  local TEST_PROFILE
  TEST_PROFILE="${1-}"
  case "${TEST_PROFILE-}" in
    *"/.bashrc" | *"/.bash_profile" | *"/.zshrc" | *"/.zprofile")
      return
    ;;
    *)
      return 1
    ;;
  esac
}

#
# Outputs the location to FVM depending on:
# * The availability of $FVM_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
# FVM_SOURCE always takes precedence unless the method is "script-fvm-exec"
#
fvm_source() {
  local FVM_GITHUB_REPO
  FVM_GITHUB_REPO="${FVM_INSTALL_GITHUB_REPO:-fvm-sh/fvm}"
  local FVM_VERSION
  FVM_VERSION="${FVM_INSTALL_VERSION:-$(fvm_latest_version)}"
  local FVM_METHOD
  FVM_METHOD="$1"
  local FVM_SOURCE_URL
  FVM_SOURCE_URL="$FVM_SOURCE"
  if [ "_$FVM_METHOD" = "_script-fvm-exec" ]; then
    FVM_SOURCE_URL="https://raw.githubusercontent.com/${FVM_GITHUB_REPO}/${FVM_VERSION}/fvm-exec"
  elif [ "_$FVM_METHOD" = "_script-fvm-bash-completion" ]; then
    FVM_SOURCE_URL="https://raw.githubusercontent.com/${FVM_GITHUB_REPO}/${FVM_VERSION}/bash_completion"
  elif [ -z "$FVM_SOURCE_URL" ]; then
    if [ "_$FVM_METHOD" = "_script" ]; then
      FVM_SOURCE_URL="https://raw.githubusercontent.com/${FVM_GITHUB_REPO}/${FVM_VERSION}/fvm.sh"
    elif [ "_$FVM_METHOD" = "_git" ] || [ -z "$FVM_METHOD" ]; then
      FVM_SOURCE_URL="https://github.com/${FVM_GITHUB_REPO}.git"
    else
      fvm_echo >&2 "Unexpected value \"$FVM_METHOD\" for \$FVM_METHOD"
      return 1
    fi
  fi
  fvm_echo "$FVM_SOURCE_URL"
}

fvm_download() {
  if fvm_has "curl"; then
    curl --fail --compressed -q "$@"
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

install_fvm_from_git() {
  local INSTALL_DIR
  INSTALL_DIR="$(fvm_install_dir)"
  local FVM_VERSION
  FVM_VERSION="${FVM_INSTALL_VERSION:-$(fvm_latest_version)}"
  if [ -n "${FVM_INSTALL_VERSION:-}" ]; then
    # Check if version is an existing ref
    if command git ls-remote "$(fvm_source "git")" "$FVM_VERSION" | fvm_grep -q "$FVM_VERSION" ; then
      :
    # Check if version is an existing changeset
    elif ! fvm_download -o /dev/null "$(fvm_source "script-fvm-exec")"; then
      fvm_echo >&2 "Failed to find '$FVM_VERSION' version."
      exit 1
    fi
  fi

  local fetch_error
  if [ -d "$INSTALL_DIR/.git" ]; then
    # Updating repo
    fvm_echo "=> fvm is already installed in $INSTALL_DIR, trying to update using git"
    command printf '\r=> '
    fetch_error="Failed to update fvm with $FVM_VERSION, run 'git fetch' in $INSTALL_DIR yourself."
  else
    fetch_error="Failed to fetch origin with $FVM_VERSION. Please report this!"
    fvm_echo "=> Downloading fvm from git to '$INSTALL_DIR'"
    command printf '\r=> '
    mkdir -p "${INSTALL_DIR}"
    if [ "$(ls -A "${INSTALL_DIR}")" ]; then
      # Initializing repo
      command git init "${INSTALL_DIR}" || {
        fvm_echo >&2 'Failed to initialize fvm repo. Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" remote add origin "$(fvm_source)" 2> /dev/null \
        || command git --git-dir="${INSTALL_DIR}/.git" remote set-url origin "$(fvm_source)" || {
        fvm_echo >&2 'Failed to add remote "origin" (or set the URL). Please report this!'
        exit 2
      }
    else
      # Cloning repo
      command git clone "$(fvm_source)" --depth=1 "${INSTALL_DIR}" || {
        fvm_echo >&2 'Failed to clone fvm repo. Please report this!'
        exit 2
      }
    fi
  fi
  # Try to fetch tag
  if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin tag "$FVM_VERSION" --depth=1 2>/dev/null; then
    :
  # Fetch given version
  elif ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin "$FVM_VERSION" --depth=1; then
    fvm_echo >&2 "$fetch_error"
    exit 1
  fi
  command git -c advice.detachedHead=false --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" checkout -f --quiet FETCH_HEAD || {
    fvm_echo >&2 "Failed to checkout the given version $FVM_VERSION. Please report this!"
    exit 2
  }
  if [ -n "$(command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" show-ref refs/heads/master)" ]; then
    if command git --no-pager --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet 2>/dev/null; then
      command git --no-pager --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet -D master >/dev/null 2>&1
    else
      fvm_echo >&2 "Your version of git is out of date. Please update it!"
      command git --no-pager --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch -D master >/dev/null 2>&1
    fi
  fi

  fvm_echo "=> Compressing and cleaning up git repository"
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" reflog expire --expire=now --all; then
    fvm_echo >&2 "Your version of git is out of date. Please update it!"
  fi
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" gc --auto --aggressive --prune=now ; then
    fvm_echo >&2 "Your version of git is out of date. Please update it!"
  fi
  return
}

install_fvm_as_script() {
  local INSTALL_DIR
  INSTALL_DIR="$(fvm_install_dir)"
  local FVM_SOURCE_LOCAL
  FVM_SOURCE_LOCAL="$(fvm_source script)"
  local FVM_EXEC_SOURCE
  FVM_EXEC_SOURCE="$(fvm_source script-fvm-exec)"
  local FVM_BASH_COMPLETION_SOURCE
  FVM_BASH_COMPLETION_SOURCE="$(fvm_source script-fvm-bash-completion)"

  # Downloading to $INSTALL_DIR
  mkdir -p "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/fvm.sh" ]; then
    fvm_echo "=> fvm is already installed in $INSTALL_DIR, trying to update the script"
  else
    fvm_echo "=> Downloading fvm as script to '$INSTALL_DIR'"
  fi
  fvm_download -s "$FVM_SOURCE_LOCAL" -o "$INSTALL_DIR/fvm.sh" || {
    fvm_echo >&2 "Failed to download '$FVM_SOURCE_LOCAL'"
    return 1
  } &
  fvm_download -s "$FVM_EXEC_SOURCE" -o "$INSTALL_DIR/fvm-exec" || {
    fvm_echo >&2 "Failed to download '$FVM_EXEC_SOURCE'"
    return 2
  } &
  fvm_download -s "$FVM_BASH_COMPLETION_SOURCE" -o "$INSTALL_DIR/bash_completion" || {
    fvm_echo >&2 "Failed to download '$FVM_BASH_COMPLETION_SOURCE'"
    return 2
  } &
  for job in $(jobs -p | command sort)
  do
    wait "$job" || return $?
  done
  chmod a+x "$INSTALL_DIR/fvm-exec" || {
    fvm_echo >&2 "Failed to mark '$INSTALL_DIR/fvm-exec' as executable"
    return 3
  }
}

fvm_try_profile() {
  if [ -z "${1-}" ] || [ ! -f "${1}" ]; then
    return 1
  fi
  fvm_echo "${1}"
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
fvm_detect_profile() {
  if [ "${PROFILE-}" = '/dev/null' ]; then
    # the user has specifically requested NOT to have fvm touch their profile
    return
  fi

  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    fvm_echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''

  if [ "${SHELL#*bash}" != "$SHELL" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ "${SHELL#*zsh}" != "$SHELL" ]; then
    if [ -f "$HOME/.zshrc" ]; then
      DETECTED_PROFILE="$HOME/.zshrc"
    elif [ -f "$HOME/.zprofile" ]; then
      DETECTED_PROFILE="$HOME/.zprofile"
    fi
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    for EACH_PROFILE in ".profile" ".bashrc" ".bash_profile" ".zprofile" ".zshrc"
    do
      if DETECTED_PROFILE="$(fvm_try_profile "${HOME}/${EACH_PROFILE}")"; then
        break
      fi
    done
  fi

  if [ -n "$DETECTED_PROFILE" ]; then
    fvm_echo "$DETECTED_PROFILE"
  fi
}

#
# Check whether the user has any globally-installed flutter in their system
# and warn them if so.
#
fvm_check_global_flutter() {
  local FLUTTER_COMMAND
  FLUTTER_COMMAND="$(command -v flutter 2>/dev/null)" || return 0
  [ -n "${FVM_DIR}" ] && [ -z "${FLUTTER_COMMAND%%"$FVM_DIR"/*}" ] && return 0

  # shellcheck disable=SC2016
  fvm_echo '=> You currently have flutter installed globally. It will no'
  # shellcheck disable=SC2016
  fvm_echo '=> longer be linked to the active version of Flutter when you install a new flutter'
  # shellcheck disable=SC2016
  fvm_echo '=> with `fvm`; and it may (depending on how you construct your `$PATH`)'
  # shellcheck disable=SC2016
  fvm_echo '=> override the binaries of flutter installed with `fvm`:'
  fvm_echo

  fvm_echo '=> If you wish to uninstall it at a later point (or re-install it under your'
  # shellcheck disable=SC2016
  fvm_echo '=> `fvm` Flutters), you can remove them from the system Flutter as follows:'
  fvm_echo
  fvm_echo '     $ fvm use system'
  fvm_echo
}

fvm_do_install() {
  if [ -n "${FVM_DIR-}" ] && ! [ -d "${FVM_DIR}" ]; then
    if [ -e "${FVM_DIR}" ]; then
      fvm_echo >&2 "File \"${FVM_DIR}\" has the same name as installation directory."
      exit 1
    fi

    if [ "${FVM_DIR}" = "$(fvm_default_install_dir)" ]; then
      mkdir "${FVM_DIR}"
    else
      fvm_echo >&2 "You have \$FVM_DIR set to \"${FVM_DIR}\", but that directory does not exist. Check your profile files and environment."
      exit 1
    fi
  fi
  # Disable the optional which check, https://www.shellcheck.net/wiki/SC2230
  # shellcheck disable=SC2230
  if fvm_has xcode-select && [ "$(xcode-select -p >/dev/null 2>/dev/null ; echo $?)" = '2' ] && [ "$(which git)" = '/usr/bin/git' ] && [ "$(which curl)" = '/usr/bin/curl' ]; then
    fvm_echo >&2 'You may be on a Mac, and need to install the Xcode Command Line Developer Tools.'
    # shellcheck disable=SC2016
    fvm_echo >&2 'If so, run `xcode-select --install` and try again. If not, please report this!'
    exit 1
  fi
  if [ -z "${METHOD}" ]; then
    # Autodetect install method
    if fvm_has git; then
      install_fvm_from_git
    elif fvm_has curl || fvm_has wget; then
      install_fvm_as_script
    else
      fvm_echo >&2 'You need git, curl, or wget to install fvm'
      exit 1
    fi
  elif [ "${METHOD}" = 'git' ]; then
    if ! fvm_has git; then
      fvm_echo >&2 "You need git to install fvm"
      exit 1
    fi
    install_fvm_from_git
  elif [ "${METHOD}" = 'script' ]; then
    if ! fvm_has curl && ! fvm_has wget; then
      fvm_echo >&2 "You need curl or wget to install fvm"
      exit 1
    fi
    install_fvm_as_script
  else
    fvm_echo >&2 "The environment variable \$METHOD is set to \"${METHOD}\", which is not recognized as a valid installation method."
    exit 1
  fi

  fvm_echo

  local FVM_PROFILE
  FVM_PROFILE="$(fvm_detect_profile)"
  local PROFILE_INSTALL_DIR
  PROFILE_INSTALL_DIR="$(fvm_install_dir | command sed "s:^$HOME:\$HOME:")"

  SOURCE_STR="\\nexport FVM_DIR=\"${PROFILE_INSTALL_DIR}\"\\n[ -s \"\$FVM_DIR/fvm.sh\" ] && \\. \"\$FVM_DIR/fvm.sh\"  # This loads fvm\\n"

  # shellcheck disable=SC2016
  COMPLETION_STR='[ -s "$FVM_DIR/bash_completion" ] && \. "$FVM_DIR/bash_completion"  # This loads fvm bash_completion\n'
  BASH_OR_ZSH=false

  if [ -z "${FVM_PROFILE-}" ] ; then
    local TRIED_PROFILE
    if [ -n "${PROFILE}" ]; then
      TRIED_PROFILE="${FVM_PROFILE} (as defined in \$PROFILE), "
    fi
    fvm_echo "=> Profile not found. Tried ${TRIED_PROFILE-}~/.bashrc, ~/.bash_profile, ~/.zprofile, ~/.zshrc, and ~/.profile."
    fvm_echo "=> Create one of them and run this script again"
    fvm_echo "   OR"
    fvm_echo "=> Append the following lines to the correct file yourself:"
    command printf "${SOURCE_STR}"
    fvm_echo
  else
    if fvm_profile_is_bash_or_zsh "${FVM_PROFILE-}"; then
      BASH_OR_ZSH=true
    fi
    if ! command grep -qc '/fvm.sh' "$FVM_PROFILE"; then
      fvm_echo "=> Appending fvm source string to $FVM_PROFILE"
      command printf "${SOURCE_STR}" >> "$FVM_PROFILE"
    else
      fvm_echo "=> fvm source string already in ${FVM_PROFILE}"
    fi
    # shellcheck disable=SC2016
    if ${BASH_OR_ZSH} && ! command grep -qc '$FVM_DIR/bash_completion' "$FVM_PROFILE"; then
      fvm_echo "=> Appending bash_completion source string to $FVM_PROFILE"
      command printf "$COMPLETION_STR" >> "$FVM_PROFILE"
    else
      fvm_echo "=> bash_completion source string already in ${FVM_PROFILE}"
    fi
  fi
  if ${BASH_OR_ZSH} && [ -z "${FVM_PROFILE-}" ] ; then
    fvm_echo "=> Please also append the following lines to the if you are using bash/zsh shell:"
    command printf "${COMPLETION_STR}"
  fi

  # Source fvm
  # shellcheck source=/dev/null
  \. "$(fvm_install_dir)/fvm.sh"

  fvm_check_global_flutter

  fvm_reset

  fvm_echo "=> Close and reopen your terminal to start using fvm or run the following to use it now:"
  command printf "${SOURCE_STR}"
  if ${BASH_OR_ZSH} ; then
    command printf "${COMPLETION_STR}"
  fi
}

#
# Unsets the various functions defined
# during the execution of the install script
#
fvm_reset() {
  unset -f fvm_has fvm_install_dir fvm_latest_version fvm_profile_is_bash_or_zsh \
    fvm_source fvm_download install_fvm_from_git \
    install_fvm_as_script fvm_try_profile fvm_detect_profile fvm_check_global_flutter \
    fvm_do_install fvm_reset fvm_default_install_dir fvm_grep
}

[ "_$FVM_ENV" = "_testing" ] || fvm_do_install

} # this ensures the entire script is downloaded #