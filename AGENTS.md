# AGENTS.md

## 仓库结构

此仓库包含两个独立的 Ansible role，无 monorepo 工具链。

```
ansibleroles/
├── mysql_deploy/      # MySQL 集群部署 + 备份管理
└── seaweedfs_deploy/  # SeaweedFS 分布式存储部署
```

## 关键命令

### seaweedfs_deploy

```bash
# 一键部署（语法检查 → ping → 部署 → 健康检查）
./deploy.sh [production|staging]

# 按组件单独部署
ansible-playbook playbook.yml --tags master
ansible-playbook playbook.yml --tags volume
ansible-playbook playbook.yml --tags filer
ansible-playbook playbook.yml --tags s3gw
```

### mysql_deploy

详见 `mysql_deploy/AGENTS.md`。

```bash
ansible-playbook playbooks/deploy_cluster.yml -i inventory.ini
ansible-playbook playbooks/mysqldump_backup.yml -i inventory.ini
ansible-playbook playbooks/xtrabackup_backup.yml -i inventory.ini
ansible-playbook tests/test.yml
```

## 架构要点

- **seaweedfs_deploy**: 三节点集群，Master 用 Raft（`-raftHashicorp`），Volume 按机架分布，副本策略 `010`
  - 组件端口：Master 9333, Volume 8080, Filer 8888, S3 8333
  - 部署脚本 `deploy.sh` 含健康检查，遍历 node1-3 检测各端口
  - 所有角色依赖 `seaweedfs-common`（用户/目录/二进制/系统调优）
- **mysql_deploy**: 主从复制集群，支持 mysqldump 和 XtraBackup 两种备份方案

## 安全注意事项

- `group_vars/all.yml` 中的 JWT 密钥和 S3 密钥均为示例占位符，生产环境需用 Ansible Vault 加密
- `mysql_deploy/defaults/main.yml` 中的密码同样为示例
- 自签名 TLS 证书由 `seaweedfs-common/tasks/tls.yml` 自动生成（10 年有效期）

## 测试与检查

- 无 CI、lint、typecheck 工具
- 唯一验证方式：`ansible-playbook --syntax-check` 和部署后的健康检查
- `playbooks/bootstrap.yml` 会在部署前检查 OS 类型和磁盘空间（`/data` 需 ≥ 50GB）
