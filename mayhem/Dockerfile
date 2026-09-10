# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org base image
# (ghcr.io/savantenvs/base). The base provides debian + clang/llvm + libFuzzer + Python 3.13 + the
# identities + the build-contract ENV. parliament (duo-labs/parliament) is a PURE-PYTHON package
# (an AWS IAM policy linter), so this image:
#   1. (root, ONLINE — the only networked step) bakes a pinned Python toolchain under
#      /opt/toolchains/python: a wheelhouse of every dependency the harness/oracle needs (atheris,
#      pytest, parliament's runtime deps json-cfg/pyyaml/boto3/jmespath, setuptools for pkg_resources)
#      and a venv installed FROM that wheelhouse with --no-index (SPEC §6.2 item 8 / §6.5 Python).
#      The wheelhouse stays in the image, so re-installs never need PyPI.
#   2. (mayhem, offline-capable) compiles the ELF launcher shims and runs the behavioral oracle via
#      build.sh / test.sh. parliament itself is NOT pip-installed: the harness, the test runner and
#      the CLI probe import it from the source tree (/mayhem/parliament) so a PATCH-tier edit is
#      what gets fuzzed and graded — build.sh therefore needs neither pip nor the network.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t parliament-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Declared for parity with the build contract (no default, so the base's ASan+UBSan ENV flows
# through); parliament has no native code of its own to sanitize — the fuzzed code is Python
# under Atheris, and the shims are plain exec() wrappers.
ARG SANITIZER_FLAGS

# Python toolchain location — fixed, $HOME-independent (SPEC §6.2 item 8), so the PATCH tier's
# air-gapped build.sh re-run resolves the same interpreter + packages under any identity.
ENV PY_TOOLCHAIN=/opt/toolchains/python \
    VIRTUAL_ENV=/opt/toolchains/python/venv \
    PATH=/opt/toolchains/python/venv/bin:${PATH}

# The (networked) dependency step, as root. The base's Debian Python has no ensurepip, so the venv
# is created --without-pip and populated by the system pip's --python mode. Every version is pinned
# for reproducibility; `pip wheel` fetches/builds the wheels into the wheelhouse, and the install
# then runs strictly --no-index from it (proving the wheelhouse is complete).
# setuptools<81 is required: parliament/__init__.py imports pkg_resources at runtime.
USER root
RUN set -eux; \
    python3 -m venv --without-pip "$VIRTUAL_ENV"; \
    PINS="atheris==3.1.0 pytest==9.1.1 setuptools==80.10.2 \
          boto3==1.43.91 botocore==1.43.91 s3transfer==0.19.2 urllib3==2.7.0 python-dateutil==2.9.0.post0 six==1.17.0 \
          jmespath==1.1.0 PyYAML==6.0.3 json-cfg==0.4.2 kwonly-args==1.0.10 \
          iniconfig==2.3.0 packaging==26.3 pluggy==1.6.0 Pygments==2.21.0"; \
    /usr/bin/pip wheel --no-cache-dir --wheel-dir "$PY_TOOLCHAIN/wheelhouse" $PINS; \
    /usr/bin/pip --python "$VIRTUAL_ENV/bin/python3" install --no-cache-dir --no-index \
        --find-links="$PY_TOOLCHAIN/wheelhouse" $PINS; \
    chmod -R a+rX "$PY_TOOLCHAIN"; \
    "$VIRTUAL_ENV/bin/python3" -c 'import atheris, jsoncfg, yaml, pytest, pkg_resources; print("python toolchain ok")'

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git history)
# is copied to /mayhem as `mayhem`; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Compile the ELF launcher shims (Mayhem needs an ELF target, not a .py) and check the harness imports.
RUN bash mayhem/build.sh

# Run parliament's real pytest known-answer suite + CLI known-answer probes at build time; a failing
# suite fails the build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
