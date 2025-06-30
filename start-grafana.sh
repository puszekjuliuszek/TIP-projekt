#!/bin/bash
echo "🚀 Uruchamiam port-forward dla Grafana..."
echo "Grafana będzie dostępna pod: http://localhost:3000"
echo "Login: admin, Hasło: admin123"
echo "Aby zatrzymać, naciśnij Ctrl+C"
kubectl port-forward -n monitoring svc/grafana 3000:3000
