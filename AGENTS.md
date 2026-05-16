# AGENTS.md

Ansible 自动化部署角色集合（MySQL 8.0 主从 + SeaweedFS 集群）。

## 项目结构

```
ansibleroles/
├── mysql_deploy/       # 独立 Ansible Role（Galaxy 兼容）
│   ├── playbooks/      # deploy_cluster.yml, mysqldump_backup.yml, xtrabackup_backup.yml
│   ├── tasks/main.yml  # 20 步骤二进制部署（import_tasks 引入）
│   ├── templates/      # my.cnf.j2, mysql.service.j2, 备份脚本 *.j2
│   ├── defaults/       # 所有可配置变量（密码占位，生产必改）
│   ├── tests/          # test.yml（语法检查 + 模板渲染 + shell/systemd 验证）
│   └── files/          # 放置 mysql-*.tar.xz 二进制包（需手动下载放入）
└── seaweedfs_deploy/   # 独立 Ansible 项目（含多个 role）
    ├── playbook.yml    # 入口：import bootstrap + 顺序部署 master/volume/filer/s3gw
    ├── group_vars/     # all.yml：集群 IP、端口、JWT 密钥
    └── roles/
        ├── seaweedfs-common/   # 用户、下载、sysctl、limits、TLS
        ├── seaweedfs-master/
        ├── seaweedfs-volume/
        ├── seaweedfs-filer/    # 含 s3.json.j2
        └── seaweedfs-s3gw/
```

## 关键命令

### MySQL（从项目根执行）
```bash
# 测试（语法 + 模板 + shell 语法检查）
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/tests/test.yml

# 部署主从集群
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/playbooks/deploy_cluster.yml

# 单独配置备份
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/playbooks/mysqldump_backup.yml
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/playbooks/xtrabackup_backup.yml
```

### SeaweedFS
```bash
ansible-playbook -i <inventory> seaweedfs_deploy/playbook.yml
```

## 约定与注意事项

- Tasks 描述用中文；保留 `#SPDX-License-Identifier: MIT-0` 头
- 所有 playbook 使用 `become: yes`
- **密码变量是占位符**（`mysqlRootPassword`、`jwt_signing_key` 等），生产必改，推荐 Ansible Vault 加密
- MySQL 二进制包放 `mysql_deploy/files/`，配置在 `defaults/main.yml`
- `mysqld --initialize` 幂等守卫：`creates: auto.cnf`
- `mysqlRootPassword` 在备份 playbook 可从 `MYSQL_ROOT_PASSWORD` 环境变量读取：`{{ lookup('env', 'MYSQL_ROOT_PASSWORD') }}`
- Inventory (`tests/inventory`) 使用占位 IP（192.168.x.x），部署前需替换
- MySQL 测试中 `systemd-analyze verify` 默认 `ignore_errors: yes`
- SeaweedFS 无测试套件；bootstrap 要求 `/data` 可用空间 >= 50G

## 架构陷阱

### MySQL: playbook 用 import_tasks 而不是 roles:

`deploy_cluster.yml` 用 `import_tasks: ../tasks/main.yml` 引入部署任务，**不是** `roles:` 方式。
这意味着 `defaults/main.yml` 和 `handlers/main.yml` 不会被自动加载。
所有模板需要的变量必须在 playbook 的 `vars:` 中显式声明（已补全），新增变量时也要注意。

### SeaweedFS: TLS 默认启用但曾是死代码

之前 `common/tasks/tls.yml` 未被 `main.yml` 引入，但 `tls_enabled: true` 默认开启，
导致 service 启动时因找不到证书文件而失败。现在已修复（`import_tasks: tls.yml` when `tls_enabled`）。

### 包管理差异

- `percona-xtrabackup-24` 在 Ubuntu 22.04+ 上包名不同（可能需 `percona-xtrabackup-80`），安装失败被 `ignore_errors` 静默吞掉。
  脚本会被正常下发，但 xtrabackup 可能不可用。
- SeaweedFS 从 GitHub 直接下载二进制（`unarchive remote_src=yes`），无需本地准备包。
