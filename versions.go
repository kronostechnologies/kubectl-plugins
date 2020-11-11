package main

import (
	"context"
	"flag"
	"fmt"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
	"path/filepath"
	"regexp"
	"strings"
)

func sanitizeVersion(version string) string {
	vr, e := regexp.Compile("^(?:version-|v)([0-9])")
	if e != nil {
		fmt.Println(e)
	}
	return vr.ReplaceAllString(version, "${1}")
}

func main() {
	debug := flag.Bool("debug", false, "debug output")

	var kubeconfig *string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}
	flag.Parse()

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	// create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	deployments, err := clientset.AppsV1().Deployments("").List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		panic(err.Error())
	}



	for _, item := range deployments.Items {
		version := item.Labels["app.kubernetes.io/version"]
		if strings.TrimSpace(version) == "" {
			if *debug {
				fmt.Println(item.Name, "has no version")
			}
			continue
		}

		// Is main component
		instance := item.Labels["app.kubernetes.io/instance"]
		name := item.Labels["app.kubernetes.io/name"]
		component := item.Labels["app.kubernetes.io/component"]

		name = getMainComponentName(instance, name)

		if item.Name != name && item.Name != fmt.Sprintf("%s-%s", component){
			if *debug {
				fmt.Println(item.Name, "mismatch for", name)
			}
			continue
		}

		fmt.Println(name, sanitizeVersion(version))
	}

}

func getMainComponentName(instance string, name string) string {
	r, _ := regexp.Compile(fmt.Sprintf("^%s(-.*)?$", instance))
	if !r.MatchString(name) {
		name = fmt.Sprintf("%s-%s", instance, name)
	}
	return name
}
