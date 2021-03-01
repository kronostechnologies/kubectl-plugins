#!/bin/bash

set -e;

KUBECTL_DIR="$(realpath ~/bin)"

FILES=~/kronos/kubectl-plugins/kubectl-*.sh
for LOCAL_FILEPATH in $FILES
do
    REAL_PATH=$(realpath $LOCAL_FILEPATH)
    BASENAME="$(basename $LOCAL_FILEPATH)"
    TOOL_NAME="${BASENAME%.sh}"
    KUBECTL_FILE="$KUBECTL_DIR/$TOOL_NAME"
    ln -s -f $LOCAL_FILEPATH $KUBECTL_FILE
    echo "Kubernetes plugin $TOOL_NAME installed."
done
