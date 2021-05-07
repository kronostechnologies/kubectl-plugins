#!/bin/bash

set -e;

readonly CTX_POST_FIX=".k8s.equisoft.io"

printUsage () {
    echo -e "
This script copies a given file to/from a specified Kubernetes pod:

        kubectl eqcp <sourceFilePath> <destinationFilePath> [OPTIONS]

<sourceFilePath> source file path, must have format <pod|context>:<filePath> if is a kubernetes pod
<destinationFilePath> destination file path, must have format <pod|context>:<filePath> if is a kubernetes pod

If you use context as the path to your pod, the first pod found will be used.

OPTIONS
        -c <context> Use specific context
        -n <namespace> Use specific namespace
        -o <container> Use a specific container

EXAMPLES
        kubectl eqcp ~/path/to/local/file equisoft-plan-worker-7612a51-55a24:path/to/pod/file
        kubectl eqcp ca-accp:path/to/pod/file ~/path/to/local/file
        kubectl eqcp ca-accp:path/to/pod/file ~/path/to/local/file -n equisoft-plan -c ca-accp -o equisoft-plan" 1>&2;
    exit 1;
}

command_exists () {
    type "$1" &> /dev/null;
}

listAllPods () {
    kubectl --request-timeout=2 --context $CONTEXT -n $NAMESPACE get pods  --field-selector=status.phase=Running -o=name | sed -e 's/pod\///' | grep -v "memcached" | grep -v "frontend" | grep -v "cron";
}

listPods () {
    if [[ "$NAMESPACE" == "equisoft-connect" || "$NAMESPACE" == "equisoft-plan" ]]; then
        listAllPods | grep "worker";
    else
        listAllPods;
    fi
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
    done < <(kubectl --request-timeout=2 --context $CONTEXT get namespaces --no-headers)
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
      printf '\e[31m%b\e[0m\n' "Invalid context (environment): $1. Must be in$validContexts";
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
      printf '\e[31m%b\e[0m\n' "Invalid namespace (app): $1. Must be in$validNamespaces";
      exit 1;
    fi
}

useDefaultContainer () {
    validContainers=($(kubectl --request-timeout=2 --context $CONTEXT get pods -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].name}'));
    if [[ "${#validContainers[@]}" -ne "1" ]]; then
        CONTAINER="$NAMESPACE";
    fi
}

useContainer () {
    validContainers=($(kubectl --request-timeout=2 --context $CONTEXT get pods -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].name}'));
    if [[ "$validContainers" == *"$1"* ]]; then
        CONTAINER="$1"
    else
        printf '\e[33m%b\e[0m\n' "Invalid container: $1. Must be in $validContainers";
        exit 1;
    fi
}

useDefaultPod () {
    IFS=' ';
    read -r -a pod_names <<< $(listPods);
    if [[ -z ${pod_names[0]} ]]; then
        printf '\e[31m%b\e[0m\n' "No pod found for namespace $NAMESPACE";
        exit 1;
    else
        echo "${pod_names[0]}";
    fi
}

usePod () {
    FULL_PATH=$1
    POD=${FULL_PATH%:*}
    PATH_TO_FILE=${FULL_PATH#*:}
    validContexts=$(listValidContexts);
    if [[ "$validContexts" == *" $POD "* ]]; then
        POD=$(useDefaultPod)
        echo "$POD:$PATH_TO_FILE"
    else
        echo $FULL_PATH
    fi
}

cp () {
    command="kubectl cp --context $CONTEXT -n $NAMESPACE $SOURCE $DESTINATION";
    if [[ $CONTAINER ]]; then
        printf '\e[36m%b\e[0m\n' "Copy file: $SOURCE to $DESTINATION. (Using container \"$CONTAINER\")";
        $command+="-c $CONTAINER";
    else
        printf '\e[36m%b\e[0m\n' "Copy file: $SOURCE to $DESTINATION. (Using default container)";
    fi
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

if [[ $SOURCE == *":"* ]]; then
    SOURCE=$(usePod $SOURCE)
else
    DESTINATION=$(usePod $DESTINATION)
fi

if [[ $container ]]; then
    useContainer $container;
else
    useDefaultContainer;
fi

cp
