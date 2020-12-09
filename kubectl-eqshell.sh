#!/bin/bash

set -e;

readonly CTX_POST_FIX=".k8s.equisoft.io"

printUsage () {
    echo -e "
This script opens a shell on a Kubernetes pod:

        kubectl eqshell [<pod>] [-c <context>] [-n <namespace>] [OPTIONS]

<context> must be in $(listValidContexts)
<namespace> must be in $(listValidNamespaces)
OPTIONS
        -l Lists running pod names for namespace.
        -i Specifies pod to connect to by index." 1>&2;
    exit 1;
}

# Get source real dir: Upstreams symlinks.
SOURCE="${BASH_SOURCE[0]}";
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)";
    SOURCE="$(readlink "$SOURCE")";
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE";
done
DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)";

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
        currentNamespace="$(kubectl config view --minify | grep namespace:)"
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

usePodSulSide () {
    IFS=' ';
    read -r -a pod_names <<< $(listPods);
    if [[ -z ${pod_names[0]} ]]; then
        echo "No pod found for namespace $NAMESPACE";
        exit 1;
    else
        POD="${pod_names[0]}";
    fi
}

usePodByIndex () {
    INDEX=$1
    IFS=' ';
    read -r -a pod_names <<< $(listPods | xargs);
    if [[ -z ${pod_names[$INDEX]} ]]; then
        echo "Pod index not found for namespace $NAMESPACE";
        exit 1;
    else
        POD="${pod_names[$INDEX]}";
    fi
}

printSpecifyPodWarning () {
    echo "Please specify a pod to connect to (Protip: list them with '-a' option).";
    exit 1;
}

connect () {
    availableContainers=($(kubectl --request-timeout=2 --context $CONTEXT get pods -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].name}'));
    command="kubectl --request-timeout=2 --context $CONTEXT -n $NAMESPACE exec -it $POD";
    if [[ "${#availableContainers[@]}" -eq "1" ]]; then
        echo "Connecting in $PRETTY_CONTEXT environment on \"$NAMESPACE:$POD\" in its default container!";
    else
        echo "Connecting in $PRETTY_CONTEXT environment on \"$NAMESPACE:$POD\" in its container \"$NAMESPACE\"!";
        command+=" -c $NAMESPACE";
    fi
    envContextPrefix="! grep -q 'kboi PS1' /root/.bashrc && echo -ne '\n# kboi PS1\nexport PS1=\\\"[$env] \\\$PS1\\\"' >> /root/.bashrc; /bin/bash";
    command+=" -- /bin/bash -c \"$envContextPrefix\"";
    eval $command;
}

OPTIND=1;
while getopts "lhc:n:p:i:" option; do
    case "${option}" in
        l)
            getList=true;
            ;;
        c)
            context=${OPTARG};
            ;;
        n)
            namespace=${OPTARG};
            ;;
        i)
            podIndex=${OPTARG};
            ;;
        :)
            printSpecifyPodWarning;
            ;;
        *)
            printUsage;
            ;;
    esac
done
shift $((OPTIND-1));

POD=$1

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

if [[ $getList ]]; then
    listPods
    exit 0;
elif [[ $POD ]]; then
    true;
elif [[ $podIndex ]]; then
    usePodByIndex $podIndex
else
    usePodSulSide
fi

connect;
