#!/bin/bash
# deploy_fluent-bit.sh
set -e

# 設定ファイルを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/cluster-config.env" ]; then
    source "$SCRIPT_DIR/cluster-config.env"
else
    echo "エラー: cluster-config.env が見つかりません"
    exit 1
fi

# 引数チェック
if [ $# -eq 0 ]; then
    echo "使用方法: $0 <cluster-name>"
    echo "例: $0 development"
    echo "    $0 production"
    echo "    $0 sandbox"
    exit 1
fi

CLUSTER_NAME=$1
CLUSTER_NAME_UPPER=$(echo $CLUSTER_NAME | tr '[:lower:]' '[:upper:]')

# 動的に変数を取得
KUBECONFIG_VAR="${CLUSTER_NAME_UPPER}_KUBECONFIG"
ARGOCD_SERVER_VAR="${CLUSTER_NAME_UPPER}_ARGOCD_SERVER"

export KUBECONFIG="${!KUBECONFIG_VAR}"
ARGOCD_SERVER="${!ARGOCD_SERVER_VAR}"

if [ -z "$KUBECONFIG" ] || [ -z "$ARGOCD_SERVER" ]; then
    echo "エラー: クラスタ '$CLUSTER_NAME' の設定が見つかりません"
    echo "cluster-config.env を確認してください"
    exit 1
fi

echo "=== Fluent Bit デプロイ ==="
echo "対象クラスタ: $CLUSTER_NAME"
echo "Kubeconfig: $KUBECONFIG"
echo "ArgoCD サーバー: $ARGOCD_SERVER"
echo ""

# ArgoCD にログイン
echo "ArgoCD にログイン中..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -n "$ARGOCD_PASSWORD" ]; then
    argocd login $ARGOCD_SERVER --username admin --password "$ARGOCD_PASSWORD" --insecure
else
    # 既存のセッションを使用
    echo "既存のセッションを使用します"
fi

# logging namespace を作成
echo "logging namespace を作成中..."
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
echo "✓ namespace 作成完了"

# 既存の Application を確認
APP_NAME="fluent-bit"

if argocd app get $APP_NAME --server $ARGOCD_SERVER > /dev/null 2>&1; then
    echo "既存の $APP_NAME Application が存在します"
    read -p "削除して再作成しますか? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Application を削除中..."
        argocd app delete $APP_NAME --yes --server $ARGOCD_SERVER
        
        # 削除が完了するまで待機
        echo "削除完了を待機中..."
        while true; do
            if ! argocd app get $APP_NAME --server $ARGOCD_SERVER > /dev/null 2>&1; then
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
        argocd app get $APP_NAME --server $ARGOCD_SERVER
        exit 0
    fi
fi

# Application を作成
echo "$APP_NAME Application を作成中..."
argocd app create $APP_NAME \
  --server $ARGOCD_SERVER \
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

# 自動同期が完了するのを待つ
echo "自動同期の完了を待機中..."
sleep 10

echo ""
echo "Application 状態:"
argocd app get $APP_NAME --server $ARGOCD_SERVER

echo ""
echo "=== デプロイ完了 ==="
echo ""
echo "確認コマンド:"
echo "  export KUBECONFIG=$KUBECONFIG"
echo "  kubectl get pods -n logging"
echo "  kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit -f"
echo "  argocd app get $APP_NAME --server $ARGOCD_SERVER"
