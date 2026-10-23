#!/bin/sh
# kube-service-port <namespace> <service> <port-name> <new-port> — change the
# port of a Service's named port (its targetPort stays). Exits 1, leaving the
# Service alone, when it has no port of that name.

. zz-colors

eval "$(
    zz-args "Change the port of a Service's named port" "$0" "$@" <<help
- namespace namespace Namespace of the Service
- service service Service name
- port_name port_name Name of the port to change
- new_port new_port New port number
help
)"

if [ -z "$namespace" ] || [ -z "$service" ] || [ -z "$port_name" ] || [ -z "$new_port" ]; then
    zz-log e "Usage: kube-service-port <namespace> <service> <port-name> <new-port>"
    exit 1
fi

idx=$(kubectl -n "$namespace" get service "$service" -o json | jq --arg n "$port_name" '.spec.ports | map(.name) | index($n)')
if [ "$idx" = "null" ] || [ -z "$idx" ]; then
    zz-log w "Service $service in $namespace has no port named '$port_name'; leaving its ports unchanged."
    exit 1
fi
kubectl -n "$namespace" patch service "$service" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/${idx}/port\",\"value\":${new_port}}]"
