#!/bin/bash

argocd app create fluent-bit \
  --repo https://github.com/your-org/your-repo.git \
  --path fluent-bit \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace logging \
  --sync-policy automated \
  --auto-prune \
  --self-heal
