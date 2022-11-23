flutter() {
  local local_version="$(fvm_current_local)"
  if [ -n "${local_version}" ]; then
    if ! fvm_is_version_installed "${local_version}"; then
      fvm_err "version ${local_version} in ${FLUTTER_VERSION_FILE} is not installed yet."
      return 1
    fi
    local flutter_path="$(fvm_version_path "${local_version}")"
    local cmd="${flutter_path}/bin/flutter $@"
    eval $cmd
    return
  fi
  local global_version="$(fvm_current_global)"
  if [ -n "${global_version}" ]; then
    if ! fvm_is_version_installed "${global_version}"; then
      fvm_err "version ${global_version} in ${FVM_DIR}/${FLUTTER_VERSION_FILE} is not installed yet."
      return 1
    fi
    local flutter_path="$(fvm_version_path "${global_version}")"
    local cmd="${flutter_path}/bin/flutter $@"
    eval $cmd
    return
  fi
  if [ -n "${FVM_SYSTEM_FLUTTER}" ]; then
    local cmd="$FVM_SYSTEM_FLUTTER $@"
    eval $cmd
    return
  fi
  fvm_echo "no flutter found"
}