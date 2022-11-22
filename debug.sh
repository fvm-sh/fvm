

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

fvm_debug() {
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
      if command ls -l "$(fvm_command_info "${tool}" | command awk '{print $1}')" | fvm_grep -q busybox; then
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
}