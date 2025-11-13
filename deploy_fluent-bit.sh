#!/bin/bash
# deploy_fluent-bit.sh
set -e

# 引数チェック
if [ $# -eq 0 ]; then
    echo "使用方法: $0 <cluster-name>"
    echo "例: $0 development"
    echo "    $0 production"
    echo "    $0 sandbox"
    exit 1
fi

CLUSTER_NAME=$1

# クラスタ設定
case $CLUSTER_NAME in
    production)
        export KUBECONFIG=/home/jaist-lab/.kube/config-production
        ARGOCD_SERVER="172.16.100.101"
        ;;
    development)
        export KUBECONFIG=/home/jaist-lab/.kube/config-development
        ARGOCD_SERVER="172.16.100.121"
        ;;
    sandbox)
        export KUBECONFIG=/home/jaist-lab/.kube/config-sandbox
        ARGOCD_SERVER="172.16.100.131"
        ;;
    *)
        echo "エラー: 未知のクラスタ名: $CLUSTER_NAME"
        echo "使用可能なクラスタ: development, production, sandbox"
        exit 1
        ;;
esac

echo "=== Fluent Bit デプロイ ==="
echo "対象クラスタ: $CLUSTER_NAME"
echo "Kubeconfig: $KUBECONFIG"
echo ""


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

        # 削除が完了するまで待機
        echo "削除完了を待機中..."
        while true; do
            if ! argocd app get fluent-bit > /dev/null 2>&1; then
                break
            fi
            echo -n "."
            sleep 2
        done
        echo ""
        echo "✓ 削除完了"

        # 追加の待機時間
        echo "安全のため追加で5秒待機..."
        sleep 5
    else
        echo "既存の Application を使用します"
        echo "手動同期を実行..."
        argocd app sync fluent-bit --retry-limit 3
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

# 自動同期が開始されるのを待つ
echo "自動同期の開始を待機中..."
sleep 5

# 同期状態を監視
echo "同期状態を確認中..."
for i in {1..30}; do
    SYNC_STATUS=$(argocd app get fluent-bit -o json | jq -r '.status.sync.status' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(argocd app get fluent-bit -o json | jq -r '.status.health.status' 2>/dev/null || echo "Unknown")

    echo "同期状態: $SYNC_STATUS, ヘルス状態: $HEALTH_STATUS"

    if [[ "$SYNC_STATUS" == "Synced" ]] && [[ "$HEALTH_STATUS" == "Healthy" ]]; then
        echo "✓ デプロイ成功"
        break
    fi

    if [ $i -eq 30 ]; then
        echo "⚠ タイムアウト: 同期状態を確認してください"
    fi

    sleep 2
done

# 最終状態を確認
echo ""
echo "Application 状態:"
argocd app get fluent-bit

echo ""
echo "=== デプロイ完了 ==="
echo ""
echo "確認コマンド:"
echo "  kubectl get pods -n logging"
echo "  kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit -f"
echo "  argocd app get fluent-bit"
