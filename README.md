# 关于脚本

小白利器，一键实现自动端口转发管理脚本，支持IPv4/IPv6，提供简单的命令行界面来管理端口转发规则。

支持iptables和Xray dokodemo-door转发

## 功能特点

- ✨ 支持IPv4和IPv6端口转发
- 🔄 自动检测系统环境和依赖
- 🛡️ 自动配置系统设置和防火墙规则
- 📊 可视化的规则管理界面
- 🚀 快速添加/删除转发规则
- 🔍 支持查看指定端口转发状态
- 🌐 IPv6支持检测功能

## 系统要求

- Linux操作系统（支持CentOS/Ubuntu/Debian）
- Root权限
- iptables/ip6tables
- bash 4.0+

## 安装依赖

```bash
# Debian/Ubuntu
apt-get update
apt-get install -y iptables ip6tables curl jq

# CentOS
yum install -y iptables ip6tables curl jq
```

## 使用方法

### 1. 基本使用

```bash
# 下载脚本
wget https://raw.githubusercontent.com/senma231/ipfw/main/ipfw.sh

# 添加执行权限
chmod +x ipfw.sh

# 运行脚本
./ipfw.sh
```

### 2. 命令行参数

```bash
./ipfw.sh [command] [options]

可用命令:
add <本地端口> <目标地址> <目标端口>   # 添加转发规则
del <本地端口>                        # 删除指定端口的转发规则
list                                 # 显示所有转发规则
show <本地端口>                       # 显示指定端口的转发规则
clear                               # 清除所有转发规则
```

### 3. 交互式菜单

运行脚本时不带参数将进入交互式菜单模式：

```bash
./ipfw.sh
```

菜单选项：

1. 添加转发规则
2. 删除转发规则
3. 查看所有转发规则
4. 查看指定端口转发
5. 清除所有转发规则
6. 检测IPv6支持
7. 退出

### 4. 示例用法

```bash
# 添加端口转发（将本地80端口转发到192.168.1.100的8080端口）
./ipfw.sh add 80 192.168.1.100 8080

# 删除80端口的转发规则
./ipfw.sh del 80

# 查看所有转发规则
./ipfw.sh list

# 检查特定端口的转发规则
./ipfw.sh show 80
```

## IPv6支持检测

脚本提供了全面的IPv6支持检测功能，可以检查：

- 系统IPv6状态
- IPv6地址配置
- IPv6网络连通性
- IPv6路由信息
- 公网IPv6地址可用性

## 注意事项

1. 脚本需要root权限才能运行
2. 首次运行会自动检查并配置系统环境
3. 添加规则时会自动检查端口占用情况
4. 支持TCP和UDP协议的端口转发
5. 配置会自动持久化保存

## 常见问题

**Q: 为什么无法添加转发规则？**

A: 请检查：

- 是否具有root权限
- 目标端口是否已被占用
- 系统是否已启用IP转发
- 防火墙是否正确配置

**Q: 如何持久化保存规则？**

A: 脚本会自动保存规则，系统重启后规则仍然生效。

**Q: 如何完全卸载？**

A: 运行以下命令：

```bash
./ipfw.sh clear  # 清除所有转发规则
rm -f ipfw.sh   # 删除脚本文件
```

## 贡献

欢迎提交问题和建议到Issue区，也欢迎提交Pull Request来改进代码。

## 许可证

MIT License
