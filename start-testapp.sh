#!/bin/bash
echo "🚀 Uruchamiam port-forward dla aplikacji testowych..."
echo "Fortio UI będzie dostępne pod: http://localhost:8080/fortio/"
echo "Aby zatrzymać, naciśnij Ctrl+C"
kubectl port-forward -n testapp svc/fortio-load-generator 8080:8080
