echo_heading() { echo -e "\n\033[34m$1\033[0m"; }
ok() { echo -e " \033[32m✔ $1\033[0m"; }
warn() { echo -e " \033[33m▲ $1\033[0m"; }

fail() {
  echo -e " \033[31m✖ $1\033[0m" >&2
  exit 1
}

run() {
  echo " + $*"
  "$@"
}
