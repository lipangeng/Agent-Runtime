#!/bin/bash

# ======================== 颜色定义 ========================
export COLOR_DEBUG="\e[1;38;5;240m" # 深灰色（DEBUG）
export COLOR_INFO="\e[1;36m"    # 青色（INFO）
export COLOR_WARNING="\e[1;33m" # 黄色（WARNING）
export COLOR_ERROR="\e[1;31m"   # 红色（ERROR）
export COLOR_FATAL="\e[1;41;97m" # 红底白字（FATAL）
export COLOR_NORMAL="\e[0m"     # 无颜色
export COLOR_RESET="\e[0m"  # 重置

#######################################
# 打印info日志
# 青色字体，提示信息
# Arguments:
#  None
#######################################
logger_info() {
  echo -e "${COLOR_INFO}$(date "+%Y-%m-%d %T") [INFO] [${BASH_SOURCE[1]:-$0}]: $1 ${COLOR_RESET}"
}

#######################################
# 打印fatal日志
# 红底带闪烁，致命错误
# Arguments:
#  None
#######################################
logger_fatal() {
  echo -e "${COLOR_FATAL}$(date "+%Y-%m-%d %T") [FATAL] [${BASH_SOURCE[1]:-$0}]: $1 ${COLOR_RESET}"
}

#######################################
# 打印error日志
# 红色字体，执行错误信息
# Arguments:
#  None
#######################################
logger_error() {
  echo -e "${COLOR_ERROR}$(date "+%Y-%m-%d %T") [ERROR] [${BASH_SOURCE[1]:-$0}]: $1 ${COLOR_RESET}"
}

#######################################
# 打印Warning日志
# 黄色文本
# Arguments:
#######################################
logger_warning() {
  echo -e "${COLOR_WARNING}$(date "+%Y-%m-%d %T") [WARNING] [${BASH_SOURCE[1]:-$0}]: $1 ${COLOR_RESET}"
}

#######################################
# 打印debug日志
# 灰色信息
# Arguments:
#  None
#######################################
logger_debug() {
  echo -e "${COLOR_DEBUG}$(date "+%Y-%m-%d %T") [DEBUG] [${BASH_SOURCE[1]:-$0}]: $1 ${COLOR_RESET}"
}

#######################################
# 打印无级别日志
# Arguments:
#  None
#######################################
logger() {
  echo -e "${COLOR_NORMAL}$(date "+%Y-%m-%d %T") [${BASH_SOURCE[1]:-$0}]: $1 ${COLOR_RESET}"
}

#######################################
# 运行初始化文件
# process_init_files [file [file [...]]]
# Arguments: [file [file [...]]]
#  None
#######################################
process_init_files() {
  # 检查是否有文件参数
  if [ $# -eq 0 ]; then
    logger_warning "No files to process." >&2
    return
  fi

  # 创建一个数组来存储文件参数
  local files=()

  # 对文件数组进行排序，并正确读取所有文件
  local read_file
  while read -r -d '' read_file; do
    files+=("$read_file")
  done < <(printf '%s\0' "$@" | sort -z -V)

  echo
  local file
  for file in "${files[@]}"; do
    case "${file}" in
      *.sh)
        if [ -x "${file}" ]; then
          logger_info "Running ${file}"
          "$file"
        else
          logger_info "Sourcing ${file}"
          . "${file}"
        fi
        ;;
      *)
        logger_info "No file,ignoring $file"
        ;;
    esac
    echo
  done
}


#######################################
# 导出方法到环境变量中
# Globals:
# Arguments:
#  None
#######################################
export_functions() {
  export -f logger logger_info logger_fatal logger_error logger_warning logger_debug
}

#######################################
# 入口函数
# Arguments:
#  None
#######################################
main() {
  set -e

  if [ "$1" = "--" ]; then
    shift  # 把这个“终结符”扔掉，处理后面的真正命令
  fi

  # 打印说明信息
  if [ -f "/entrypoint.d/usage.sh" ]; then
    /entrypoint.d/usage.sh
  else
    logger_warning "/entrypoint.d/usage.sh not found, skipping usage info"
  fi

  # ======================== 打印启动信息 ========================
  echo -e "\e[1;32m=============================================="
  echo -e "  Container Startup"
  echo -e "  Start Time: $(date "+%Y-%m-%d %H:%M:%S")"
  echo -e "==============================================${COLOR_RESET}"
  echo

  # 导出常用方法
  export_functions

  # 系统内置初始化脚本
  if [ -z "${SKIP_SYSTEM_ENTRYPOINT}" ]; then
    process_init_files /entrypoint.d/system/*
  else
    logger "skip system entrypoint"
  fi
  # 自定义初始化脚本
  if [ -z "${SKIP_USER_ENTRYPOINT}" ]; then
    process_init_files /entrypoint.d/user/*
  else
    logger "skip user entrypoint"
  fi

  # Exec anything
  echo -e "\e[1;32m=============================================="
  echo -e "  Start Main Process"
  echo -e "  Init Completed At: $(date "+%Y-%m-%d %H:%M:%S")"
  echo -e "  Exec Command: $*"
  echo -e "==============================================${COLOR_RESET}"
  echo

  if [ -n "${REAL_ENTRYPOINT:-}" ]; then
    # 配置了值，进一步检查文件是否存在且可读
    if [ -f "${REAL_ENTRYPOINT}" ] && [ -r "${REAL_ENTRYPOINT}" ]; then
      logger_info "Execute real entrypoint via source: ${REAL_ENTRYPOINT}"
      exec "${REAL_ENTRYPOINT}" "$@"
    else
      # 配置了值但文件不满足条件，输出警告日志
      logger_fatal "Real entrypoint configured (${REAL_ENTRYPOINT}) but file is missing or not readable!"
      return 1
    fi
  else
    # 如果没有参数，直接退出
    [ $# -eq 0 ] && return

    # 1. 尝试检测第一个参数是否为可执行命令（标准模式）
    # 注意：如果 $1 是 "ls -la"，command -v 必然失败，会进入 else
    if command -v "$1" > /dev/null 2>&1; then
        logger_info "Standard command mode detected. Executing with 'exec \"\$@\"'"
        exec "$@"
    else
        logger_warning "Single string command detected. Falling back to Shell parsing mode"
        # 针对 K8s 传单字符串的硬限制：
        # 使用 "$*" 将所有参数拼成一个长字符串。
        # 即使字符串里有：--title "My App"
        # 这里的 sh -c 会正确地把 "My App" 当做一个整体参数传递给程序。
        exec /bin/sh -c "exec $*"
    fi
  fi
}

main "$@"
