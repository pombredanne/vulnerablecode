#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p libxml2 libxslt perl poetry rename
#!nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixos-20.09.tar.gz

# This scripts generates the mock poetry project files.

set -e

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SETUP_PY=$(realpath "$THIS_DIR/../../setup.py")
REQUIREMENTS_TXT=$(realpath "$THIS_DIR/../../requirements.txt")
POETRY_FILES=(pyproject.toml poetry.lock)

# Prevent "ValueError: ZIP does not support timestamps before 1980"
# See nixpkgs manual.
unset SOURCE_DATE_EPOCH

# Sanity checks.
for f in $SETUP_PY $REQUIREMENTS_TXT ; do
  test -f "$f" || { echo "File $SETUP_PY doesn't exist! Aborting ..." ; exit 1; }
done

# Extract some value from a variable/keyword argument in setup.py (removing
# (hopefully) all surrounding characters).
getFromSetupPy () {
  VARIABLE_NAME=$1
  grep -E "$VARIABLE_NAME\s?=" "$SETUP_PY" | sed -e 's/^.*= *//' -e 's/,.*$//' -e 's/"//g' -e "s/'//g"
}

NAME=$(getFromSetupPy name)
VERSION=$(getFromSetupPy version)
DESC=$(getFromSetupPy desc)
AUTHOR=$(getFromSetupPy author)
AUTHOR_EMAIL=$(getFromSetupPy author_email)
AUTHORS="$AUTHOR <$AUTHOR_EMAIL>"
LICENSE=$(getFromSetupPy license)
PYTHON="^3.8"
DEFINE_MAIN_DEPS_INTERACTIVELY="no"
DEFINE_DEV_DEPS_INTERACTIVELY="no"
CONFIRM_GENERATION="yes"

# Make sure we run from here.
cd "$THIS_DIR"

# Remove poetry files from (failed) previos runs.
rm -f "${POETRY_FILES[@]}"

# Create the pyproject.toml file using `poetry init` which runs interactively
# and asks a couple of questions. Answer them using predefined values.
poetry init <<EOF
$NAME
$VERSION
$DESC
$AUTHORS
$LICENSE
$PYTHON
$DEFINE_MAIN_DEPS_INTERACTIVELY
$DEFINE_DEV_DEPS_INTERACTIVELY
$CONFIRM_GENERATION
EOF

# Convert requirements.txt entries to pyproject.toml entries.
# https://github.com/python-poetry/poetry/issues/663
perl -pe 's/([<=>]+)/:$1/' "$REQUIREMENTS_TXT" | tr '\n' ' ' | xargs -t -I {} bash -c "poetry add {}"

# Rename the mock project files.
rename -f 's/$/.generated/' "${POETRY_FILES[@]}"