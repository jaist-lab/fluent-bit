#!/bin/bash
# deploy_fluent-bit.sh

set -e

echo "=== Fluent Bit デプロイ ==="

# 環境の選択

echo "対象の環境設定:"
echo $KUBECONFIG

# logging namespace を作成
echo "logging namespace を作成中..."
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
echo "✓ namespace 作成完了"

# 既存の Application を確認
if argocd app get fluent-bit > /dev/null 2>&1; then
    echo "既存の fluent-bit Application が存在します"
    read -p "削除して再作成しますか? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Application を削除中..."
        argocd app delete fluent-bit --yes
        sleep 5
        echo "✓ 削除完了"
    else
        echo "既存の Application を使用します"
        argocd app sync fluent-bit
        exit 0
    fi
fi

# Application を作成
echo "fluent-bit Application を作成中..."
argocd app create fluent-bit \
  --repo https://github.com/jaist-lab/fluent-bit.git \
  --path fluent-bit \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace logging \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true

if [ $? -eq 0 ]; then
    echo "✓ Application 作成完了"
else
    echo "✗ Application 作成失敗"
    exit 1
fi

# 同期を実行
echo "同期を開始..."
argocd app sync fluent-bit

# 状態を確認
echo "Application 状態:"
argocd app get fluent-bit

echo ""
echo "=== デプロイ完了 ==="
echo ""
echo "確認コマンド:"
echo "  kubectl get pods -n logging"
echo "  kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit -f"
echo "  argocd app get fluent-bit"
