#!/bin/bash
# debug_fluent-bit.sh

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <cluster-name>"
    echo "例: $0 development"
    exit 1
fi

CLUSTER_NAME=$1

case $CLUSTER_NAME in
    development)
        export KUBECONFIG=/home/jaist-lab/.kube/config-development
        ;;
    production)
        export KUBECONFIG=/home/jaist-lab/.kube/config-production
        ;;
    sandbox)
        export KUBECONFIG=/home/jaist-lab/.kube/config-sandbox
        ;;
    *)
        echo "エラー: 未知のクラスタ名: $CLUSTER_NAME"
        exit 1
        ;;
esac

echo "=== Fluent Bit デバッグ情報 ==="
echo "クラスタ: $CLUSTER_NAME"
echo "Kubeconfig: $KUBECONFIG"
echo ""

echo "=== クラスタ接続確認 ==="
kubectl cluster-info
echo ""

echo "=== Fluent Bit Pod 一覧 ==="
kubectl get pods -n logging -l app.kubernetes.io/name=fluent-bit -o wide
echo ""

echo "=== Fluent Bit ログ（最新100行） ==="
kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit --tail=100
echo ""

echo "=== Fluent Bit メトリクス ==="
POD_NAME=$(kubectl get pods -n logging -l app.kubernetes.io/name=fluent-bit -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    echo "Pod: $POD_NAME"
    kubectl exec -n logging $POD_NAME -- curl -s http://localhost:2020/api/v1/metrics | head -50
    echo ""
    
    echo "=== Loki 接続テスト ==="
    kubectl exec -n logging $POD_NAME -- curl -v http://loki.monitoring.svc.cluster.local:3100/ready
    echo ""
else
    echo "Fluent Bit Pod が見つかりません"
fi

echo "=== Loki Pod 確認 ==="
kubectl get pods -n monitoring -l app=loki
echo ""

echo "=== ConfigMap 確認 ==="
kubectl get configmap -n logging -l app.kubernetes.io/name=fluent-bit
echo ""
