# Kubectl Plugins
This repo contains many useful scripts to help you dealing with tasks around Kubernetes.

## Install
[Equisoft bootcamp](https://github.com/kronostechnologies/bootcamp/tree/master/k8s) has a script that installs all the plugins listed below.

## Usage
Fire, make sure your scripts are installed by running `kubectl plugin list` in your terminal. Then you run these scripts through `kubectl` (ex: `kubectl eqshell -h`)

## Plugins
| Name    | Description                                          | Example                                                                                 |
|---------|------------------------------------------------------|-----------------------------------------------------------------------------------------|
| eqshell | Open a shell on a Kubernetes pod                     | kubectl eqshell                                                                         |
| eqcp    | Copy a given file to/from a specified Kubernetes pod | kubectl eqcp ~/Downloads/hello.txt equisoft-connect-worker-456146:/srv/shared/hello.txt |
| eqtool  | Run specified app tool on a Kubernetes pod           | kubectl eqtool                                                                          |

## Contribution
Do not hesitate to contribute by adding your own scripts. Everyone can benefit from it.
Make sure to include a relevant --help option to your script and to add its description to this file.
The [Kubernetes Official Guide](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/) is a great starting point.
