#!/bin/bash

argocd app create fluent-bit \
  --repo https://github.com/jaist-lab/fluent-bit.git \
  --path fluent-bit \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace logging \
  --sync-policy automated \
  --auto-prune \
  --self-heal
