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
    development)
        export KUBECONFIG=/home/jaist-lab/.kube/config-development
        DEST_NAME="development"  # ArgoCD に登録した名前
        ;;
    production)
        export KUBECONFIG=/home/jaist-lab/.kube/config-production
        DEST_NAME="production"
        ;;
    sandbox)
        export KUBECONFIG=/home/jaist-lab/.kube/config-sandbox
        DEST_NAME="sandbox" 
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
echo "ArgoCD デプロイ先: $DEST_NAME"
echo ""

# logging namespace を作成
echo "logging namespace を作成中..."
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
echo "✓ namespace 作成完了"

# 既存の Application を確認
APP_NAME="fluent-bit-${CLUSTER_NAME}"

if argocd app get $APP_NAME > /dev/null 2>&1; then
    echo "既存の $APP_NAME Application が存在します"
    read -p "削除して再作成しますか? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Application を削除中..."
        argocd app delete $APP_NAME --yes
        
        # 削除が完了するまで待機
        echo "削除完了を待機中..."
        while true; do
            if ! argocd app get $APP_NAME > /dev/null 2>&1; then
                break
            fi
            echo -n "."
            sleep 2
        done
        echo ""
        echo "✓ 削除完了"
        echo "安全のため追加で5秒待機..."
        sleep 5
    else
        echo "既存の Application を使用します"
        argocd app get $APP_NAME
        exit 0
    fi
fi

# Application を作成
echo "$APP_NAME Application を作成中..."
argocd app create $APP_NAME \
  --repo https://github.com/jaist-lab/fluent-bit.git \
  --path fluent-bit \
  --dest-name "$DEST_NAME" \
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

# 自動同期が完了するのを待つ
echo "自動同期の完了を待機中..."
sleep 10

echo ""
echo "Application 状態:"
argocd app get $APP_NAME

echo ""
echo "=== デプロイ完了 ==="
echo ""
echo "確認コマンド:"
echo "  export KUBECONFIG=$KUBECONFIG"
echo "  kubectl get pods -n logging"
echo "  kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit -f"
echo "  argocd app get $APP_NAME"
