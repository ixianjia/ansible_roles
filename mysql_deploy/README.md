# MySQL 集群部署操作手册（二进制包方式）

## 目录

- [项目概述](#项目概述)
- [环境要求](#环境要求)
- [准备工作](#准备工作)
- [快速部署](#快速部署)
- [Playbook 详解](#playbook-详解)
- [二进制部署原理](#二进制部署原理)
- [配置详解](#配置详解)
- [备份与恢复](#备份与恢复)
- [维护操作](#维护操作)
- [测试](#测试)
- [常见问题](#常见问题)

---

## 项目概述

`mysql_deploy` 是一个 Ansible Role，使用 **MySQL 官方二进制包**自动化部署 MySQL 8.0 主从复制集群，并配置两种备份策略：

| 备份方式 | 类型 | 适用场景 |
|---------|------|---------|
| mysqldump | 逻辑备份 | 中小规模，单库粒度，支持 --single-transaction 无锁 |
| XtraBackup | 物理备份 | 大规模数据库，支持全量/增量 |

### 对比系统包管理器部署

| 特性 | 二进制包部署 | apt/yum 部署 |
|------|------------|-------------|
| 版本控制 | 精确锁定版本（如 8.0.36） | 随发行版仓库更新 |
| 目录布局 | 统一在 `/usr/local/mysql` | 分散在 `/usr/bin`、`/etc/mysql` 等 |
| 多实例 | 天然支持 | 需要额外配置 |
| 升级方式 | 替换软链接即可回滚 | 包管理器覆盖 |

---

## 环境要求

### 管理节点

- Ansible 2.2+
- Python 3

### 目标节点

- 操作系统：Ubuntu 20.04+ / Debian 11+ / CentOS 7+
- 依赖包：libaio1, libaio-dev, numactl, rsync, tar, xz-utils
- MySQL 二进制包（`mysql-VERSION-linux-glibc2.12-x86_64.tar.xz`）

### 主机组定义

Inventory 需定义以下组：

```ini
[mysql_masters]
master1 ansible_host=192.168.1.10

[mysql_slaves]
slave1 ansible_host=192.168.1.11
slave2 ansible_host=192.168.1.12

[mysql_cluster:children]
mysql_masters
mysql_slaves

[mysql_backup]
backup1 ansible_host=192.168.1.20
```

---

## 准备工作

### 1. 下载 MySQL 二进制包

从 MySQL 官网下载 Linux 通用二进制包：

```bash
# 示例: MySQL 8.0.36
wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.36-linux-glibc2.12-x86_64.tar.xz
```

### 2. 将二进制包放入角色 files/ 目录

```
mysql_deploy/playbooks/roles/mysql_deploy/files/mysql-8.0.36-linux-glibc2.12-x86_64.tar.xz
```

### 3. 配置变量

编辑 `playbooks/roles/mysql_deploy/defaults/main.yml`，主要关注：

```yaml
# 版本和包名（与 files/ 目录下的文件一致）
mysqlVersion: "8.0.36"
mysqlBinaryPackage: "mysql-8.0.36-linux-glibc2.12-x86_64.tar.xz"
mysqlDirName: "mysql-8.0.36-linux-glibc2.12-x86_64"

# 密码（生产环境必改）
mysqlRootPassword: "your_strong_password"
mysqlReplicationPassword: "your_replication_password"
```

---

## 快速部署

### 部署 MySQL 主从集群

```bash
# 从 ansibleroles 项目根目录执行
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/playbooks/deploy_cluster.yml
```

> 角色代码位于 `playbooks/roles/mysql_deploy/`，Ansible 自动从 playbook 所在目录的 `roles/` 下查找，无需额外配置 `roles_path`。

### 配置备份

```bash
# mysqldump 逻辑备份
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/playbooks/mysqldump_backup.yml

# XtraBackup 物理备份
ansible-playbook -i mysql_deploy/tests/inventory mysql_deploy/playbooks/xtrabackup_backup.yml
```

> **注意**: 实际使用请替换 `tests/inventory` 为真实的 inventory 文件。

---

## Playbook 详解

### deploy_cluster.yml — 二进制部署 + 主从复制

该 playbook 包含 **20 个步骤**，分为两个阶段：

#### 阶段一：二进制安装（通过 `roles:` 引入）

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 创建 mysql:mysql 用户/组 | uid/gid=3306 |
| 2 | 安装依赖包 | libaio, numactl, rsync, tar 等 |
| 3 | 创建数据/日志/run 目录 | `{{ mysqlDataDir }}`, `{{ mysqlLogDir }}` 等 |
| 4 | 上传二进制包 | `files/` → `/tmp/` |
| 5 | 解压到 `/usr/local/` | 使用 unarchive 模块 |
| 6 | 清理临时包 | 删除 `/tmp/` 下的压缩包 |
| 7 | 创建软链接 | `/usr/local/mysql-VERSION` → `/usr/local/mysql` |
| 8 | 配置环境变量 | `/etc/profile.d/mysql.sh` |
| 9 | 下发 my.cnf | 模板渲染至 `/etc/my.cnf` |
| 10 | **初始化数据目录** | `mysqld --initialize`，生成临时 root 密码 |
| 11 | 提取临时密码 | 从 error.log 中正则提取 |
| 12 | 保存临时密码 | 写入 `/root/.mysql_temp_password` |
| 13 | 下发 systemd 服务 | `mysql.service.j2` → `/etc/systemd/system/mysqld.service` |
| 14 | 启动 MySQL | systemd 启动，开机自启 |
| 15 | 等待 MySQL 就绪 | 端口 3306 探测，超时 60s |
| 16 | **修改 root 密码** | 使用临时密码登录，ALTER USER 设置新密码 |
| 17 | 安全加固 | 删除匿名用户、删除 test 数据库 |

> **关键**: `mysqld --initialize` 只在首次执行（`creates: auto.cnf` 守卫），幂等安全。第 10-12 步和第 16-17 步仅在初始化时触发。

#### 阶段二：主从复制配置

| 步骤 | 操作 | 说明 |
|------|------|------|
| 18 | 创建复制用户 | `REPLICATION SLAVE ON *.*` |
| 19 | 获取主库 binlog 位置 | `SHOW MASTER STATUS` |
| 20 | 配置从库链路 | `CHANGE MASTER TO` |
| 21 | 启动复制 | `START SLAVE` |
| 22 | 等待同步 | pause 3 秒 |
| 23 | 检查复制状态 | `SHOW SLAVE STATUS` |
| 24 | 断言验证 | 确保 `Slave_IO_Running: Yes` 和 `Slave_SQL_Running: Yes` |
| 25 | 输出部署信息 | 主从列表、版本、安装方式 |

### mysqldump_backup.yml — 配置逻辑备份

- 创建 `backup_user` 用户（`SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER`）
- 安装 gzip、mailutils
- 生成备份脚本 `/usr/local/bin/mysqldump_backup.sh`
- 生成清理脚本 `/usr/local/bin/cleanup_backups.sh`
- 添加 cron 任务：每天 2:00 备份，3:30 清理
- 执行一次测试备份

### xtrabackup_backup.yml — 配置物理备份

- 创建 `backup_user` 用户（`RELOAD, LOCK TABLES, REPLICATION CLIENT`）
- 安装 percona-xtrabackup-24
- 生成备份脚本 `/usr/local/bin/xtrabackup_backup.sh`
- 添加 cron 任务：每天 4:00 备份
- `--dry-run` 测试模式

---

## 二进制部署原理

### 初始化流程

```
mysqld --initialize --user=mysql --basedir=/usr/local/mysql --datadir=/var/lib/mysql
```

- 创建 MySQL 系统表空间
- 生成 `auto.cnf`（server UUID）
- 生成临时 root 密码 → 写入 error.log
- 格式：`[Note] A temporary password is generated for root@localhost: xxxxxxxx`

### 密码修改流程

```
临时密码(grep error.log) → ALTER USER → 新密码(mysqlRootPassword)
```

### Path 传递路径

```
/etc/profile.d/mysql.sh  →  登录 shell 生效
备份脚本内置 PATH       →  cron 环境也可用
```

### systemd 服务特点

- `Type=notify` — mysqld 准备就绪后通知 systemd
- `Restart=on-failure` — 异常退出自动重启
- `LimitNOFILE=65535` — 文件描述符限制
- ExecStart 显式指定所有路径，不依赖 my.cnf

---

## 配置详解

### defaults/main.yml 变量说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `mysqlVersion` | `8.0.36` | MySQL 版本号 |
| `mysqlBinaryPackage` | `mysql-8.0.36-...` | 包文件名（放 files/） |
| `mysqlDirName` | `mysql-8.0.36-...` | 解压后的目录名 |
| `mysqlBaseDir` | `/usr/local/mysql` | MySQL 安装基目录（软链接） |
| `mysqlDataDir` | `/var/lib/mysql` | 数据目录 |
| `mysqlLogDir` | `/var/log/mysql` | 日志目录 |
| `mysqlRunDir` | `/var/run/mysqld` | PID/socket 目录 |
| `mysqlRootPassword` | `secure_root_password` | root 密码（**必改**） |
| `mysqlPort` | `3306` | 监听端口 |
| `mysqlMaxConnections` | `200` | 最大连接数 |
| `mysqlInnodbBufferPoolSize` | `1G` | InnoDB 缓冲池 |

### my.cnf 配置要点

**复制相关：**
- `binlog_format=ROW` — 行级复制，数据一致性好
- `sync_binlog=1` + `innodb_flush_log_at_trx_commit=1` — 双 1 配置，保证不丢数据
- `binlog_expire_logs_seconds=604800` — binlog 保留 7 天（8.0 新版参数）
- `skip_slave_start` — 从库重启后不自动启动复制，手动确认

**性能相关：**
- `innodb_buffer_pool_size={{ mysqlInnodbBufferPoolSize }}` — 建议设为物理内存的 60-70%
- `innodb_flush_method=O_DIRECT` — 绕过文件系统缓存
- `innodb_autoinc_lock_mode=2` — 交错锁模式，高并发插入性能更好

**安全相关：**
- `skip-name-resolve` — 不反解 DNS，避免 DNS 故障导致连接慢
- `skip-external-locking` — 避免外部锁竞争
- `lower_case_table_names=1` — 表名大小写不敏感

### server-id 生成

```
{{ inventory_hostname | hash('md5') }}
```

基于主机名的 MD5 哈希，确保集群内唯一。

---

## 备份与恢复

### mysqldump 逻辑备份

脚本路径：`/usr/local/bin/mysqldump_backup.sh`

**特点：**
- 逐库备份，排除系统库（information_schema, performance_schema, mysql, sys）
- `--single-transaction` 无锁备份，对业务无影响
- 包含存储过程、触发器、事件
- `--set-gtid-purged=OFF` — 兼容非 GTID 模式
- 默认压缩（.sql.gz），7 天后自动清理
- 备份失败/成功均邮件通知

**手动执行：**
```bash
sudo /usr/local/bin/mysqldump_backup.sh
```

**单库恢复：**
```bash
# 找到对应备份包
cd /backup/mysql
tar -xzf mysqldump_full_20250101_020000.tar.gz
cd mysqldump_20250101_020000

# 解压并恢复
gunzip < mydb_20250101_020000.sql.gz | mysql -u root -p
```

**全库恢复：**
```bash
for f in *.sql.gz; do
  db_name=$(basename "$f" | cut -d_ -f1)
  gunzip < "$f" | mysql -u root -p "$db_name"
done
```

### XtraBackup 物理备份

脚本路径：`/usr/local/bin/xtrabackup_backup.sh`

**支持参数：**
```bash
sudo /usr/local/bin/xtrabackup_backup.sh --full          # 全量备份
sudo /usr/local/bin/xtrabackup_backup.sh --incremental    # 增量备份
sudo /usr/local/bin/xtrabackup_backup.sh --dry-run        # 测试运行
```

**特点：**
- 多线程并行（默认 4 线程）
- `--no-lock --safe-slave-backup` — 对主库无锁，从库安全备份
- 支持压缩
- 自动清理过期备份

**全量恢复步骤：**
```bash
# 1. 停止 MySQL
systemctl stop mysqld

# 2. 备份原数据目录（应急回滚）
mv /var/lib/mysql /var/lib/mysql.bak

# 3. 解压备份包
tar -xzf /backup/mysql/xtrabackup_full_20250101_040000.tar.gz -C /restore

# 4. 准备备份（apply redo log）
xtrabackup --prepare --target-dir=/restore/xtrabackup_20250101_040000

# 5. 恢复到数据目录
xtrabackup --copy-back --target-dir=/restore/xtrabackup_20250101_040000 \
  --datadir=/var/lib/mysql

# 6. 修复权限
chown -R mysql:mysql /var/lib/mysql

# 7. 启动 MySQL
systemctl start mysqld
```

### 清理脚本

脚本路径：`/usr/local/bin/cleanup_backups.sh`

每天 3:30 由 cron 触发，删除超过 7 天的：
- `mysqldump_full_*.tar.gz`
- `xtrabackup_full_*.tar.gz`
- 遗留的 xtrabackup/mysqldump 临时目录

---

## 维护操作

### 查看 MySQL 运行状态

```bash
# 服务状态
systemctl status mysqld

# 进程
ps aux | grep mysqld

# 端口
ss -tlnp | grep 3306

# 错误日志
tail -100 /var/log/mysql/error.log
```

### 查看复制状态

```bash
# 从库上执行
/usr/local/mysql/bin/mysql -u root -p -e "SHOW SLAVE STATUS\G"

# 重点字段
# Slave_IO_Running: Yes    — IO 线程正常
# Slave_SQL_Running: Yes   — SQL 线程正常
# Seconds_Behind_Master: 0 — 延迟为 0
```

### 手动切换主从

```bash
# 从库停止复制
STOP SLAVE;
RESET SLAVE ALL;

# 新主库创建复制用户
CREATE USER 'replicator'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';

# 新从库指向新主
CHANGE MASTER TO
  MASTER_HOST='new_master_ip',
  MASTER_USER='replicator',
  MASTER_PASSWORD='password',
  MASTER_LOG_FILE='mysql-bin.xxxxxx',
  MASTER_LOG_POS=xxx;
START SLAVE;
```

### 升级 MySQL 版本

```bash
# 1. 下载新版二进制包到 playbooks/roles/mysql_deploy/files/
# 2. 修改 playbooks/roles/mysql_deploy/defaults/main.yml
mysqlVersion: "8.0.37"
mysqlBinaryPackage: "mysql-8.0.37-linux-glibc2.12-x86_64.tar.xz"
mysqlDirName: "mysql-8.0.37-linux-glibc2.12-x86_64"

# 3. 重新执行 playbook（会自动升级）
ansible-playbook -i inventory playbooks/deploy_cluster.yml
```

升级原理：新版解压到 `/usr/local/mysql-8.0.37` → 软链接切换到新版 → 重启服务。

### 安全建议

1. **修改默认密码**：`mysqlRootPassword` 和 `mysqlReplicationPassword`
2. **使用 Ansible Vault** 加密敏感变量：
   ```bash
   ansible-vault encrypt playbooks/roles/mysql_deploy/defaults/main.yml
   ansible-playbook --ask-vault-pass playbooks/deploy_cluster.yml
   ```
3. **生产环境建议**：
   - `mysqlBindAddress` 改为内网 IP
   - 开启防火墙限制 3306 端口访问来源
   - 开启审计日志

---

## 测试

项目包含完整的测试套件：

```bash
ansible-playbook -i tests/inventory tests/test.yml
```

测试内容覆盖：
1. ✅ 所有 playbook 语法检查
2. ✅ 模板和 playbook 文件存在性
3. ✅ Jinja2 模板渲染（含所有变量）
4. ✅ Shell 脚本语法检查（`bash -n`）
5. ✅ systemd unit 语法验证
6. ✅ my.cnf 配置项检查
7. ✅ 自动清理临时文件

---

## 常见问题

### Q1: mysqld --initialize 报错

**现象**: `Failed to find valid data directory` 或 `ibdata1 already exists`

**原因**: 数据目录已非空（重跑）

**解决**: 这是幂等守卫生效，跳过初始化即可。如果确实需要重新初始化：
```bash
systemctl stop mysqld
rm -rf /var/lib/mysql/*
rm -f /var/lib/mysql/auto.cnf
# 重新执行 playbook
```

### Q2: root 密码修改失败

**现象**: `Access denied` 或 `ERROR 1820`

**原因**: 临时密码已过期，或密码中有特殊字符

**解决**: 
```bash
# 安全模式跳过密码验证
/usr/local/mysql/bin/mysqld_safe --skip-grant-tables &
# 手动修改密码
```

### Q3: 从库复制报错

**常见错误及解决：**

```
Last_IO_Error: Got fatal error 1236
  → binlog 位置不匹配，用 SHOW SLAVE STATUS 确认
  → 或执行 STOP SLAVE; RESET SLAVE; 重新配置

Last_SQL_Error: Error executing row event
  → 数据冲突，设置 slave_skip_errors 或手动修复
  → 或跳过错误: STOP SLAVE; SET GLOBAL sql_slave_skip_counter=1; START SLAVE;

Last_IO_Error: error connecting to master
  → 防火墙 3306 端口未放通
  → 复制用户密码不匹配
```

### Q4: 备份脚本执行失败

**检查日志：**
```bash
# mysqldump 日志
tail -50 /var/log/mysql/mysqldump_backup.log

# xtrabackup 日志
tail -50 /var/log/mysql/xtrabackup_backup.log

# 清理日志
tail -50 /var/log/mysql/cleanup_backups.log
```

**常见原因：**
- 备份目录 `/backup/mysql` 磁盘空间不足
- PATH 环境问题（特别是在 cron 下）：脚本已内置 `export PATH`，无需额外配置
- xtrabackup 未安装：`apt install percona-xtrabackup-24`

### Q5: 如何修改备份时间

修改 `playbooks/roles/mysql_deploy/defaults/main.yml` 中的 cron 表达式：

```yaml
backupMysqldumpSchedule: "0 2 * * *"    # 每天 2:00
backupXtrabackupSchedule: "0 4 * * *"   # 每天 4:00
```

重新执行对应 playbook 即可更新 cron。

### Q6: 如何扩容从库

```bash
# 1. 新机器配置好 inventory
# 2. 执行部署
ansible-playbook -i new_inventory playbooks/deploy_cluster.yml -l new_slave
# 3. 检查复制状态
```
