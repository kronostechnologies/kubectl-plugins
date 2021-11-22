#!/bin/bash

set -e;

readonly CTX_POST_FIX=".k8s.equisoft.io"

printUsage () {
    echo -e "
This script opens a shell on a Kubernetes pod:

        kubectl eqshell [<pod>] [OPTIONS]

<pod> Connect to specific pod

OPTIONS
        -c <context> Use specific context
        -n <namespace> Use specific namespace
        -o <container> Use specific container
        -i <index> Specifies pod to connect to by index
        -l Lists running pod names for namespace

<context> must be in prod|ca-accp|dsf-prod|dsf-accp|ia-prod|ia-accp|us-prod|us-accp|unstable
<namespace> must be in account-service|admail|antivirus|argo-events|auth-server|backup|calculatrices|cert-manager|chartmuseum|circleci-exporter|cpanel|cpanel2|datagateways|default|environment-chooser|equisoft-connect|equisoft-plan|equisoft-plan-express|flux-system|gatekeeper-system|gearmand|getmail|github-exporter|importpdftool|investor-profile|kube-node-lease|kube-public|kube-system|logdna|login|mediawiki|monitoring|pdf-api|premium-calculator|purecloud|rabbitmq|redirector|scan|voice|zpush" 1>&2;
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
    done < <(kubectl --request-timeout=2 --context $CONTEXT get namespaces --no-headers)
    echo $namespaces
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

usePodByIndex () {
    INDEX=$1
    IFS=' ';
    read -r -a pod_names <<< $(listPods | xargs);
    if [[ -z ${pod_names[$INDEX]} ]]; then
        printf '\e[31m%b\e[0m\n' "Pod index not found for namespace $NAMESPACE";
        exit 1;
    else
        POD="${pod_names[$INDEX]}";
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

printSpecifyPodWarning () {
    printf '\e[33m%b\e[0m\n' "Please specify a pod to connect to (Protip: list them with '-a' option).";
    exit 1;
}

connect () {
    command="kubectl --request-timeout=2 --context $CONTEXT -n $NAMESPACE exec -it $POD";
    if [[ $CONTAINER ]]; then
        printf '\e[36m%b\e[0m\n' "Connecting in $PRETTY_CONTEXT environment on \"$NAMESPACE:$POD\" in its container \"$CONTAINER\"!";
        command+=" -c $CONTAINER";
    else
        printf '\e[36m%b\e[0m\n' "Connecting in $PRETTY_CONTEXT environment on \"$NAMESPACE:$POD\" in its default container!";
    fi
    envContextPrefix="! grep -q 'kboi PS1' /root/.bashrc && echo -ne '\n# kboi PS1\nexport PS1=\\\"[$env] \\\$PS1\\\"' >> /root/.bashrc; /bin/bash";
    command+=" -- /bin/bash -c \"$envContextPrefix\"";
    eval $command;
}

OPTIND=1;
while getopts "lhc:n:p:o:i:" option; do
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
        o)
            container=${OPTARG};
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
fi

if [[ $POD ]]; then
    true;
elif [[ $podIndex ]]; then
    usePodByIndex $podIndex
else
    useDefaultPod
fi

if [[ $container ]]; then
    useContainer $container;
else
    useDefaultContainer;
fi

connect;
