#!/bin/bash

set -e;

readonly CTX_POST_FIX=".k8s.equisoft.io"

printUsage () {
    echo -e "
This script copies a given file to/from a specified Kubernetes pod:

        kubectl eqcp <sourceFilePath> <destinationFilePath> [OPTIONS]

<sourceFilePath> source file path, must have format <pod>:<filePath> if is a kubernetes pod
<destinationFilePath> destination file path, must have format <pod>:<filePath> if is a kubernetes pod

OPTIONS
        -c <context> Use specific context, must be in$(listValidContexts)
        -n <namespace> Use specific namespace, must be in $(listValidNamespaces)
        -o <container> Specify a container to copy to by name." 1>&2;
    exit 1;
}

command_exists () {
    type "$1" &> /dev/null;
}

listValidContexts () {
    CTXs=" $(kubectl --request-timeout=2 config view -o jsonpath='{.contexts[*].name}') ";
    echo "${CTXs//$CTX_POST_FIX/}";
}

listValidNamespaces () {
    namespaces=""
    while read -r line
    do
        name="${line%% *}"
        namespaces="$namespaces $name"
    done < <(kubectl --request-timeout=2 get namespaces --no-headers)
    echo $namespaces
}

useDefaultContext () {
    if command_exists kubectx; then
        currentContext=$(kubectx -c)
    else
        currentContext=$(kubectl config current-context)
    fi
    useContext "${currentContext//$CTX_POST_FIX/}";
}

useContext () {
    validContexts=$(listValidContexts);
    if [[ "$validContexts" == *" $1 "* ]]; then
      PRETTY_CONTEXT="$1";
      CONTEXT="$1$CTX_POST_FIX";
    else
      echo "Invalid context (environment): $1. Must be in$validContexts";
      exit 1;
    fi
}

useDefaultNamespace () {
    if command_exists kubens; then
        useNamespace $(kubens -c);
    else
        currentNamespace="$(kubectl config view --context $CONTEXT --minify | grep namespace:)"
        namespacePrefix="    namespace: "
        useNamespace "${currentNamespace//$namespacePrefix/}";
    fi
}

useNamespace () {
    validNamespaces=$(listValidNamespaces);
    if [[ "$validNamespaces" == *" $1 "* ]]; then
      NAMESPACE="$1"
    else
      echo "Invalid namespace (app): $1. Must be in$validNamespaces";
      exit 1;
    fi
}

cp () {
    command="kubectl cp --context $CONTEXT -n $NAMESPACE $SOURCE $DESTINATION";
    if [[ ! -z $1 ]]; then
        $command+="-c $1";
    fi
    echo "Copy file: $SOURCE to $DESTINATION";
    eval $command;
}

if [[ $# -lt 2 ]]; then
    printUsage;
fi

# Args
SOURCE=$1;
DESTINATION=$2;

OPTIND=3;
while getopts "hc:n:o:" option; do
    case "${option}" in
        c)
            context=${OPTARG};
            ;;
        n)
            namespace=${OPTARG};
            ;;
        o)
            container=${OPTARG};
            ;;
        *)
            printUsage;
            ;;
    esac
done
shift $((OPTIND-1));

if [[ $context ]]; then
    useContext $context;
else
    useDefaultContext;
fi

if [[ $namespace ]]; then
    useNamespace $namespace;
else
    useDefaultNamespace;
fi

cp $container
