---
# MySQL Deployment and Backup Management

This Ansible role provides comprehensive MySQL cluster deployment and backup management capabilities. It includes automated deployment of MySQL replication clusters with master-slave configuration, plus robust backup solutions using both mysqldump (logical backups) and XtraBackup (physical backups).

## Features

### 🚀 Deployment Features
- **MySQL Cluster Deployment**: Automated deployment of MySQL replication clusters
- **Master-Slave Replication**: Configures MySQL replication with automatic failover support
- **High Availability**: Supports multiple master and slave configurations
- **Performance Tuning**: Optimized MySQL configuration for production environments
- **Security Hardening**: Secure MySQL installation with minimal privilege principles

### 💾 Backup Features
- **mysqldump Backup**: Automated logical backups with compression support
- **XtraBackup Support**: Physical hot backups using Percona XtraBackup
- **Incremental Backups**: Supports full and incremental backup strategies
- **Automated Cleanup**: Automatic cleanup of old backups based on retention policy
- **Email Notifications**: Comprehensive email notifications for backup status
- **Scheduled Backups**: Cron-based automated backup scheduling

### 🛡️ Management Features
- **Monitoring**: Built-in logging and monitoring capabilities
- **Security**: Secure backup storage with proper file permissions
- **Disaster Recovery**: Complete backup and restore procedures
- **Scalability**: Supports large databases and high-performance environments

## Quick Start

### 1. Installation
```bash
# Clone the repository
git clone <repository-url>
cd mysql_deploy

# Install dependencies
ansible-galaxy install -r requirements.yml
```

### 2. Configuration
```bash
# Copy and edit inventory file
cp inventory.example inventory.ini
# Edit inventory.ini with your server details
```

### 3. Deployment
```bash
# Deploy MySQL cluster
ansible-playbook playbooks/deploy_cluster.yml

# Configure backup servers
ansible-playbook playbooks/mysqldump_backup.yml
ansible-playbook playbooks/xtrabackup_backup.yml
```

## Playbooks

### 🎯 Core Playbooks

#### 1. MySQL Cluster Deployment
```bash
ansible-playbook playbooks/deploy_cluster.yml -i inventory.ini
```
Deploys MySQL replication clusters with master-slave configuration.

#### 2. mysqldump Backup Configuration
```bash
ansible-playbook playbooks/mysqldump_backup.yml -i inventory.ini
```
Configures automated logical backups using mysqldump.

#### 3. XtraBackup Configuration
```bash
ansible-playbook playbooks/xtrabackup_backup.yml -i inventory.ini
```
Configures physical backups using Percona XtraBackup.

#### 4. Test Playbook
```bash
ansible-playbook tests/test.yml
```
Validates all configurations and syntax.

## Inventory Configuration

### Basic Inventory Example
```ini
[mysql_cluster]
mysql-master-1 ansible_host=192.168.1.10
mysql-master-2 ansible_host=192.168.1.11
mysql-slave-1 ansible_host=192.168.1.12
mysql-slave-2 ansible_host=192.168.1.13

[mysql_masters]
mysql-master-1
mysql-master-2

[mysql_slaves]
mysql-slave-1
mysql-slave-2

[mysql_backup]
mysql-backup-1 ansible_host=192.168.1.20
```

### Advanced Inventory Example
```ini
# MySQL Cluster with custom variables
[mysql_cluster]
mysql-master-1 ansible_host=192.168.1.10 mysql_version=8.0 mysql_root_password=custom_password
mysql-master-2 ansible_host=192.168.1.11 mysql_version=8.0 mysql_root_password=custom_password
mysql-slave-1 ansible_host=192.168.1.12 mysql_version=8.0
mysql-slave-2 ansible_host=192.168.1.13 mysql_version=8.0

[mysql_masters]
mysql-master-1
mysql-master-2

[mysql_slaves]
mysql-slave-1
mysql-slave-2

[mysql_backup]
mysql-backup-1 ansible_host=192.168.1.20 backup_dir=/data/backup/mysql backup_retention_days=30

[mysql_cluster:vars]
mysql_version=8.0
mysql_root_password=secure_root_password
mysql_datadir=/var/lib/mysql
backup_dir=/backup/mysql
backup_retention_days=7
```

### Group Variables Example
```ini
# group_vars/mysql_cluster.yml
mysql_version: "8.0"
mysql_root_password: "{{ vault_mysql_root_password }}"
mysql_replication_user: "replicator"
mysql_replication_password: "{{ vault_mysql_replication_password }}"
mysql_datadir: "/var/lib/mysql"
mysql_bind_address: "0.0.0.0"
mysql_max_connections: 500

# group_vars/mysql_backup.yml
backup_dir: "/backup/mysql"
backup_retention_days: 7
backup_compression: true
backup_email: "dba@example.com"
monitoring_enabled: true
```

## Configuration Variables

### 🔧 MySQL Cluster Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `mysql_version` | "8.0" | MySQL server version |
| `mysql_root_password` | "secure_root_password" | MySQL root password |
| `mysql_replication_user` | "replicator" | Replication username |
| `mysql_replication_password` | "replication_password" | Replication password |
| `mysql_datadir` | "/var/lib/mysql" | MySQL data directory |
| `mysql_bind_address` | "0.0.0.0" | MySQL bind address |
| `mysql_max_connections` | 200 | Maximum connections |
| `mysql_innodb_buffer_pool_size` | "1G" | InnoDB buffer pool size |
| `mysql_innodb_log_file_size` | "256M" | InnoDB log file size |
| `mysql_cluster_name` | "mysql_cluster" | Cluster name for identification |

### 💾 Backup Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `backup_dir` | "/backup/mysql" | Backup storage directory |
| `backup_retention_days` | 7 | Number of days to retain backups |
| `backup_mysqldump_enabled` | true | Enable mysqldump backups |
| `backup_xtrabackup_enabled` | true | Enable XtraBackup |
| `backup_compression` | true | Enable backup compression |
| `backup_databases` | [] | Specific databases to backup (empty = all) |
| `backup_exclude_databases` | ["information_schema", "performance_schema", "mysql", "sys"] | Databases to exclude |
| `backup_email` | "admin@example.com" | Email for notifications |
| `backup_parallel` | 4 | Number of parallel threads for XtraBackup |

### 📊 Monitoring Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `monitoring_enabled` | true | Enable monitoring |
| `monitoring_user` | "monitor" | Monitoring username |
| `monitoring_password` | "monitor_password" | Monitoring password |

### ⚡ Performance Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `innodb_buffer_pool_size` | "1G" | InnoDB buffer pool size |
| `innodb_log_file_size` | "256M" | InnoDB log file size |
| `innodb_flush_log_at_trx_commit` | 1 | Flush log at transaction commit |
| `sync_binlog` | 1 | Synchronize binary log to disk |
| `max_connections` | 200 | Maximum concurrent connections |

### 🔐 Security Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `mysql_root_password` | "secure_root_password" | Root password (use vault for production) |
| `mysql_replication_password` | "replication_password" | Replication password |
| `backup_password` | "backup_password" | Backup user password |
| `monitoring_password` | "monitor_password" | Monitoring user password |

## Environment Variables

You can override configuration using environment variables:

```bash
export MYSQL_ROOT_PASSWORD="your_secure_password"
export BACKUP_DIR="/custom/backup/path"
ansible-playbook playbooks/deploy_cluster.yml
```

## Usage

### Deploy MySQL Cluster
1. Configure your inventory file
2. Set custom variables if needed
3. Run the deployment playbook:
   ```bash
   ansible-playbook playbooks/deploy_cluster.yml
   ```

### Configure Backup
1. Configure backup server in inventory
2. Run backup configuration:
   ```bash
   ansible-playbook playbooks/mysqldump_backup.yml
   ansible-playbook playbooks/xtrabackup_backup.yml
   ```

### Manual Backup Execution
```bash
# mysqldump backup
/usr/local/bin/mysqldump_backup.sh

# XtraBackup full backup
/usr/local/bin/xtrabackup_backup.sh --full

# XtraBackup incremental backup
/usr/local/bin/xtrabackup_backup.sh --incremental
```

## Requirements

- Ansible 2.8+
- MySQL 8.0+ server
- Percona XtraBackup (for physical backups)
- Cron for scheduled backups

## Backup Scripts

### mysqldump_backup.sh
- Creates logical backups of all databases
- Supports compression
- Automatic cleanup of old backups
- Email notifications

### xtrabackup_backup.sh
- Creates physical backups
- Supports full and incremental backups
- Compression support
- Automatic cleanup
- Email notifications

### cleanup_backups.sh
- Cleans up old backups based on retention policy
- Reports disk usage
- Removes empty directories

## Monitoring

The backup scripts log to:
- `/var/log/mysql/mysqldump_backup.log`
- `/var/log/mysql/xtrabackup_backup.log`
- `/var/log/mysql/cleanup_backups.log`

## Security

- Backup users with minimal required privileges
- Encrypted backup storage
- Secure file permissions
- Regular cleanup to prevent disk space issues

## Troubleshooting

1. Check log files for errors
2. Verify MySQL connectivity
3. Check disk space
4. Verify cron job execution
5. Test backup restoration process