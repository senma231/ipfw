# ipfw
基本命令格式
```
./ipfw.sh <command> [arguments]
```

## 可用命令列表
1、添加转发规则
```
./ipfw.sh add <local_port> <target_address> <target_port> [protocol]
# 例如:
./ipfw.sh add 80 192.168.1.100 8080 tcp    # IPv4
./ipfw.sh add 443 2001:db8::1 8443 tcp     # IPv6
```
