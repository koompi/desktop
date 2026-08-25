# shellcheck shell=bash
# Sourced by ./setup. Everything that is neither "install a package" nor "copy a
# file", one concern per file under setups/; run_setups is the order they run in.

# shellcheck source-path=SCRIPTDIR
_SETUPS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/setups"
# shellcheck source=setups/_guards.sh
source "$_SETUPS_DIR/_guards.sh"
# shellcheck source=setups/cli.sh
source "$_SETUPS_DIR/cli.sh"
# shellcheck source=setups/globalmenu.sh
source "$_SETUPS_DIR/globalmenu.sh"
# shellcheck source=setups/python.sh
source "$_SETUPS_DIR/python.sh"
# shellcheck source=setups/system.sh
source "$_SETUPS_DIR/system.sh"
# shellcheck source=setups/ai.sh
source "$_SETUPS_DIR/ai.sh"
# shellcheck source=setups/agent_memory.sh
source "$_SETUPS_DIR/agent_memory.sh"
# shellcheck source=setups/desktop.sh
source "$_SETUPS_DIR/desktop.sh"
# shellcheck source=setups/session.sh
source "$_SETUPS_DIR/session.sh"
unset _SETUPS_DIR

run_setups() {
    setup_koompi_cli
    setup_globalmenu_rs
    setup_shell_services
    setup_python_venv
    setup_groups_and_modules
    setup_suspend_hook
    setup_low_ram_defaults
    setup_local_ai
    setup_agent_memory
    setup_portals
    setup_toolkit_defaults
    setup_system_session
}
