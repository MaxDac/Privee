export NAMESPACE="default"

echo ""
echo "🔍 Checking if TLS secret has been synced to Kubernetes..."
kubectl -n "$NAMESPACE" get secret ingress-tls -o yaml | grep -E 'tls\.crt|tls\.key'

if [ $? -eq 0 ]; then
    echo "✅ TLS secret 'ingress-tls' is present in Kubernetes!"
else
    echo "⚠️  TLS secret 'ingress-tls' not found. Make sure to deploy SecretProviderClass and sync pod."
fi