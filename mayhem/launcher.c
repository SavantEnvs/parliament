/* launcher.c — a tiny ELF that exec()s a Python entry point of this repo under the pinned
 * /opt/toolchains/python interpreter, forwarding argv.
 *
 * Mayhem requires every fuzz target `cmd:` to be an ELF binary (it rejects a script / shebang
 * wrapper, and fuzz-smoke.sh checks the ELF magic). parliament (duo-labs/parliament) is pure
 * Python, so the Atheris libFuzzer harness is a `.py`. This shim is the ELF Mayhem launches; it
 * immediately execs `<PY_INTERP> <PY_SCRIPT> <args...>`, handing the libFuzzer/Atheris flags
 * straight through. The Python process then IS the libFuzzer target (it iterates inputs).
 *
 * The same shim (different -D values) fronts the test runner and the CLI known-answer probe, so
 * mayhem/test.sh drives the oracle through ELF binaries under /mayhem that the verify-repo
 * sabotage check can neuter.
 *
 * Built with $DEBUG_FLAGS (DWARF < 4) per SPEC §6.2 item 10, and dynamically linked so the
 * verify-repo sabotage oracle (LD_PRELOAD constructor) can reach it.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef PY_INTERP
#define PY_INTERP "/opt/toolchains/python/venv/bin/python3"
#endif
#ifndef PY_SCRIPT
#define PY_SCRIPT "/mayhem/mayhem/fuzz_policy.py"
#endif

int main(int argc, char **argv) {
    char **nv = (char **)malloc((size_t)(argc + 2) * sizeof(char *));
    if (!nv) return 1;
    nv[0] = (char *)PY_INTERP;
    nv[1] = (char *)PY_SCRIPT;
    for (int i = 1; i < argc; i++) nv[i + 1] = argv[i];
    nv[argc + 1] = NULL;
    execv(PY_INTERP, nv);
    /* Only reached if the pinned interpreter is missing/unrunnable: fail loudly, don't fall back
     * to some other python3 that lacks atheris and would fail in a confusing way. */
    perror("launcher: execv(" PY_INTERP ") failed");
    return 127;
}
