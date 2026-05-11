#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-production}
PLAYBOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== SeaweedFS 部署开始: $ENV ==="

cd "$PLAYBOOK_DIR"

# 语法检查
echo ">>> 检查 playbook 语法..."
ansible-playbook playbook.yml --syntax-check

# 连通性测试
echo ">>> Ping 测试..."
ansible all -m ping -o

# 部署全部组件
echo ">>> 开始部署..."
ansible-playbook playbook.yml \
  -i inventory/hosts.ini \
  -l seaweedfs \
  -v

# 部署后健康检查
echo ">>> 健康检查..."
for node in node1 node2 node3; do
  echo "--- $node ---"
  ansible $node -m shell -a "curl -sf http://localhost:9333/cluster/status || echo 'MASTER NOT READY'"
  ansible $node -m shell -a "curl -sf http://localhost:8080/status || echo 'VOLUME NOT READY'"
  ansible $node -m shell -a "curl -sf http://localhost:8888/status || echo 'FILER NOT READY'"
done

echo "=== 部署完成 ==="
