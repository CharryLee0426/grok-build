#!/bin/sh
# The `grok` command from Grok Desktop, bundled as Contents/Resources/bin/grok. Settings links
# /usr/local/bin/grok here, and the app's terminal panel has this folder on PATH.
unset CDPATH

script=$0
while [ -L "$script" ]; do
    target=$(readlink "$script")
    case $target in
        /*) script=$target ;;
        *) script=$(dirname "$script")/$target ;;
    esac
done
harness="$(cd "$(dirname "$script")/.." && pwd -P)/grok"

if [ ! -x "$harness" ]; then
    echo "grok: Grok Desktop's copy of Grok Build is missing. Reinstall Grok Desktop." >&2
    exit 127
fi

if [ "$1" = update ]; then
    echo "grok: This grok comes with Grok Desktop and updates with it. Install the latest Grok Desktop to update." >&2
    exit 1
fi

# Updates arrive with Grok Desktop; the bundled copy must not install a different version of itself.
export GROK_DISABLE_AUTOUPDATER=1
exec "$harness" "$@"
