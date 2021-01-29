#!/bin/bash

set -e;

readonly CTX_POST_FIX=".k8s.equisoft.io"

printUsage () {
    echo -e "
This script run apps tool on specified Kubernetes container:

        kubectl eqtool [OPTIONS] <cmd>

<cmd> is the tool to run (ex: ORM:Migration:Status)

OPTIONS
        -p <pod> Use specific pod
        -c <context> Use specific context
        -n <namespace> Use specific namespace
        -o <container> Specify a container." 1>&2;
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
    done < <(kubectl --request-timeout=2 --context $CONTEXT get namespaces --no-headers)
    echo $namespaces
}

listValidPods () {
    kubectl --request-timeout=2 --context $CONTEXT -n $NAMESPACE get pods --field-selector=status.phase=Running -o=name | sed -e 's/pod\///' | grep -v "memcached" | grep -v "frontend" | grep -v "cron";
}

listPods () {
    if [[ "$NAMESPACE" == "equisoft-connect" || "$NAMESPACE" == "equisoft-plan" ]]; then
        listValidPods | grep "worker";
    else
        listValidPods;
    fi
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
        currentNamespace="$(kubectl config view -context $CONTEXT --minify | grep namespace:)"
        namespacePrefix="    namespace: "
        useNamespace "${currentNamespace//$namespacePrefix/}";
    fi
}

useNamespace () {
    validNamespaces=$(listValidNamespaces);
    if [[ "$validNamespaces" == *" $1 "* ]]; then
        NAMESPACE="$1"
    else
        printf '\e[31m%b\e[0m\n' "Invalid namespace (app): $1. Must be in $validNamespaces";
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
        POD="${pod_names[0]}";
    fi
}

usePod () {
    POD="$1"
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

tool () {
    TOOL_CMD="$1";

    command="kubectl --request-timeout=2 --context $CONTEXT -n $NAMESPACE exec -it $POD"
    if [[ $CONTAINER ]]; then
        printf '\e[36m%b\e[0m\n' "Running tool in $PRETTY_CONTEXT environment on \"$NAMESPACE:$POD\" in its container \"$CONTAINER\""
        command+=" -c $CONTAINER"
    else
        printf '\e[36m%b\e[0m\n' "Running tool in $PRETTY_CONTEXT environment on \"$NAMESPACE:$POD\" in its default container"
    fi

    command+=" -- tool $TOOL_CMD"
    eval $command;
}

OPTIND=0;
while getopts "hp:c:n:o:" option; do
    case "${option}" in
        p)
            pod=${OPTARG};
            ;;
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

if [[ $pod ]]; then
    POD="$pod"
else
    useDefaultPod;
fi

if [[ $container ]]; then
    useContainer $container;
else
    useDefaultContainer;
fi

tool "$*";
