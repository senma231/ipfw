#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 脚本配置
CONFIG_DIR="/etc/auto_forward"
IPTABLES_CONFIG_DIR="$CONFIG_DIR/iptables"
IPTABLES_CONFIG_FILE="$IPTABLES_CONFIG_DIR/forwards.json"
XRAY_CONFIG_DIR="$CONFIG_DIR/xray"
XRAY_CONFIG_FILE="$XRAY_CONFIG_DIR/forwards.json"
XRAY_SYSTEM_CONFIG_DIR="/usr/local/etc/xray"
XRAY_SYSTEM_CONFIG_FILE="$XRAY_SYSTEM_CONFIG_DIR/config.json"

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        OS="unknown"
    fi
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

# 初始化配置目录
init_config_dirs() {
    mkdir -p "$IPTABLES_CONFIG_DIR"
    mkdir -p "$XRAY_CONFIG_DIR"
    mkdir -p "$XRAY_SYSTEM_CONFIG_DIR"
    
    # 初始化配置文件
    if [ ! -f "$IPTABLES_CONFIG_FILE" ]; then
        echo '[]' > "$IPTABLES_CONFIG_FILE"
    fi
    if [ ! -f "$XRAY_CONFIG_FILE" ]; then
        echo '{"inbounds":[]}' > "$XRAY_CONFIG_FILE"
    fi
    if [ ! -f "$XRAY_SYSTEM_CONFIG_FILE" ]; then
        echo '{"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}' > "$XRAY_SYSTEM_CONFIG_FILE"
    fi
}

# 检查系统配置
check_system_settings() {
    echo -e "${YELLOW}正在检查系统配置...${NC}"
    
    # 检查并启用IP转发
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        echo -e "${YELLOW}正在启用IP转发...${NC}"
        echo 1 > /proc/sys/net/ipv4/ip_forward
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        sysctl -p
    fi
    
    # 检查防火墙配置
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "active"; then
            echo -e "${YELLOW}检测到UFW防火墙正在运行，是否关闭？ [y/n]${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                ufw disable
            fi
        fi
    fi
    
    if command -v firewalld >/dev/null 2>&1; then
        if systemctl is-active firewalld >/dev/null 2>&1; then
            echo -e "${YELLOW}检测到firewalld防火墙正在运行，是否关闭？ [y/n]${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                systemctl stop firewalld
                systemctl disable firewalld
            fi
        fi
    fi
    
    echo -e "${GREEN}系统配置检查完成${NC}"
}

# 检查并配置iptables环境
check_iptables_env() {
    echo -e "${YELLOW}正在检查iptables环境...${NC}"
    
    case $OS in
        "debian"|"ubuntu")
            if ! dpkg -l | grep -q iptables; then
                echo -e "${YELLOW}正在安装iptables...${NC}"
                apt-get update
                apt-get install -y iptables
            fi
            ;;
        "centos"|"rhel"|"fedora")
            if ! rpm -q iptables; then
                echo -e "${YELLOW}正在安装iptables...${NC}"
                yum install -y iptables
            fi
            ;;
        *)
            echo -e "${RED}不支持的操作系统${NC}"
            exit 1
            ;;
    esac
    
    # 检查iptables服务
    if ! systemctl is-active iptables >/dev/null 2>&1; then
        echo -e "${YELLOW}正在启动iptables服务...${NC}"
        systemctl start iptables
        systemctl enable iptables
    fi
    
    echo -e "${GREEN}iptables环境检查完成${NC}"
}

# 检查并配置Xray环境
check_xray_env() {
    echo -e "${YELLOW}正在检查Xray环境...${NC}"
    
    if ! command -v xray >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装Xray...${NC}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    fi
    
    # 检查Xray服务
    if ! systemctl is-active xray >/dev/null 2>&1; then
        echo -e "${YELLOW}正在启动Xray服务...${NC}"
        systemctl start xray
        systemctl enable xray
    fi
    
    echo -e "${GREEN}Xray环境检查完成${NC}"
}

# 检查依赖工具
check_dependencies() {
    echo -e "${YELLOW}正在检查依赖工具...${NC}"
    
    local missing_deps=()
    
    # 检查必要的工具
    for tool in curl jq netstat iptables systemctl; do
        if ! command -v $tool >/dev/null 2>&1; then
            missing_deps+=($tool)
        fi
    done
    
    # 如果有缺失的依赖，尝试安装
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}以下工具未安装: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}正在尝试安装缺失的依赖...${NC}"
        
        case $OS in
            "debian"|"ubuntu")
                apt-get update
                apt-get install -y ${missing_deps[@]}
                ;;
            "centos"|"rhel"|"fedora")
                yum install -y ${missing_deps[@]}
                ;;
            *)
                echo -e "${RED}不支持的操作系统，请手动安装以下工具: ${missing_deps[*]}${NC}"
                exit 1
                ;;
        esac
    fi
    
    echo -e "${GREEN}依赖工具检查完成${NC}"
}

# 检查并启用IPv6支持
check_ipv6_support() {
    echo -e "${CYAN}检查IPv6支持...${NC}"
    
    # 检查是否支持IPv6
    if [ ! -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        echo -e "${YELLOW}警告: 系统可能不支持IPv6${NC}"
        return 1
    fi
    
    # 检查IPv6是否被禁用
    if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" -eq 1 ]; then
        echo -e "${YELLOW}IPv6当前被禁用，正在启用...${NC}"
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
    fi
    
    # 启用IPv6转发
    if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" -eq 0 ]; then
        echo -e "${GREEN}启用IPv6转发...${NC}"
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
    fi
    
    # 检查ip6tables命令
    if ! command -v ip6tables >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: ip6tables未安装，IPv6转发功能将不可用${NC}"
        return 1
    fi
    
    echo -e "${GREEN}IPv6支持检查完成${NC}"
    return 0
}

# 保存iptables规则
save_iptables_rules() {
    echo -e "${YELLOW}正在保存iptables规则...${NC}"
    
    case $OS in
        "debian"|"ubuntu")
            netfilter-persistent save
            ;;
        "centos"|"rhel"|"fedora")
            service iptables save
            ;;
        *)
            echo -e "${RED}不支持的操作系统，无法保存iptables规则${NC}"
            return 1
            ;;
    esac
    
    echo -e "${GREEN}iptables规则保存成功${NC}"
}

# 错误处理函数
handle_error() {
    local exit_code=$1
    local error_msg=$2
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}错误: $error_msg${NC}"
        return 1
    fi
    return 0
}

# 添加iptables转发规则
add_iptables_forward() {
    local local_port=$1
    local target_address=$2
    local target_port=$3
    local protocol=${4:-tcp}
    
    # IPv4规则
    iptables -t nat -A PREROUTING -p "$protocol" --dport "$local_port" -j DNAT --to-destination "$target_address:$target_port"
    iptables -t nat -A POSTROUTING -p "$protocol" -d "$target_address" --dport "$target_port" -j MASQUERADE
    
    # 如果支持IPv6且目标地址是IPv6地址，添加IPv6规则
    if check_ipv6_support && [[ "$target_address" =~ .*:.* ]]; then
        ip6tables -t nat -A PREROUTING -p "$protocol" --dport "$local_port" -j DNAT --to-destination "[$target_address]:$target_port"
        ip6tables -t nat -A POSTROUTING -p "$protocol" -d "$target_address" --dport "$target_port" -j MASQUERADE
    fi
    
    # 保存转发规则到配置文件
    if [ ! -f "$IPTABLES_CONFIG_FILE" ]; then
        echo "[]" > "$IPTABLES_CONFIG_FILE"
    fi
    
    local rule=$(jq -n \
        --arg local_port "$local_port" \
        --arg target_address "$target_address" \
        --arg target_port "$target_port" \
        --arg protocol "$protocol" \
        '{local_port: $local_port, target_address: $target_address, target_port: $target_port, protocol: $protocol}')
    
    jq --argjson rule "$rule" '. += [$rule]' "$IPTABLES_CONFIG_FILE" > "$IPTABLES_CONFIG_FILE.tmp"
    mv "$IPTABLES_CONFIG_FILE.tmp" "$IPTABLES_CONFIG_FILE"
    
    echo -e "${GREEN}添加转发规则: $local_port → $target_address:$target_port [$protocol]${NC}"
}

# 添加Xray转发规则
add_xray_forward() {
    local local_port=$1
    local target_address=$2
    local target_port=$3
    local protocol=${4:-tcp}
    
    # 检查端口是否已被使用
    if netstat -tuln | grep -q ":$local_port "; then
        echo -e "${RED}端口 $local_port 已被占用${NC}"
        return 1
    fi
    
    # 创建新的inbound配置
    local inbound=$(jq -n \
        --arg port "$local_port" \
        --arg address "$target_address" \
        --arg target_port "$target_port" \
        --arg protocol "$protocol" \
        '{
            port: ($port|tonumber),
            protocol: "dokodemo-door",
            settings: {
                address: $address,
                port: ($target_port|tonumber),
                network: $protocol
            },
            tag: "forward_\($port)"
        }')
    
    # 更新Xray配置
    local config=$(jq ".inbounds += [$inbound]" "$XRAY_SYSTEM_CONFIG_FILE")
    echo "$config" > "$XRAY_SYSTEM_CONFIG_FILE"
    
    # 保存规则到配置文件
    local rule=$(jq -n \
        --arg local_port "$local_port" \
        --arg target_address "$target_address" \
        --arg target_port "$target_port" \
        --arg protocol "$protocol" \
        '{local_port: $local_port, target_address: $target_address, target_port: $target_port, protocol: $protocol}')
    
    local rules=$(jq ".inbounds += [$rule]" "$XRAY_CONFIG_FILE")
    echo "$rules" > "$XRAY_CONFIG_FILE"
    
    # 重启Xray服务
    systemctl restart xray
    
    echo -e "${GREEN}Xray转发规则添加成功${NC}"
}

# 删除iptables转发规则
delete_iptables_forward() {
    local local_port=$1
    local target_address=$2
    local target_port=$3
    local protocol=${4:-tcp}
    
    # 删除IPv4规则
    iptables -t nat -D PREROUTING -p "$protocol" --dport "$local_port" -j DNAT --to-destination "$target_address:$target_port" 2>/dev/null
    iptables -t nat -D POSTROUTING -p "$protocol" -d "$target_address" --dport "$target_port" -j MASQUERADE 2>/dev/null
    
    # 如果支持IPv6且目标地址是IPv6地址，删除IPv6规则
    if check_ipv6_support && [[ "$target_address" =~ .*:.* ]]; then
        ip6tables -t nat -D PREROUTING -p "$protocol" --dport "$local_port" -j DNAT --to-destination "[$target_address]:$target_port" 2>/dev/null
        ip6tables -t nat -D POSTROUTING -p "$protocol" -d "$target_address" --dport "$target_port" -j MASQUERADE 2>/dev/null
    fi
    
    # 从配置文件中删除规则
    if [ -f "$IPTABLES_CONFIG_FILE" ]; then
        jq --arg local_port "$local_port" \
           --arg target_address "$target_address" \
           --arg target_port "$target_port" \
           --arg protocol "$protocol" \
           'del(.[] | select(.local_port == $local_port and .target_address == $target_address and .target_port == $target_port and .protocol == $protocol))' \
           "$IPTABLES_CONFIG_FILE" > "$IPTABLES_CONFIG_FILE.tmp"
        mv "$IPTABLES_CONFIG_FILE.tmp" "$IPTABLES_CONFIG_FILE"
    fi
    
    echo -e "${GREEN}删除转发规则: $local_port → $target_address:$target_port [$protocol]${NC}"
}

# 删除Xray转发规则
delete_xray_forward() {
    local local_port=$1
    
    # 更新Xray配置
    local config=$(jq ".inbounds |= map(select(.tag != \"forward_$local_port\"))" "$XRAY_SYSTEM_CONFIG_FILE")
    echo "$config" > "$XRAY_SYSTEM_CONFIG_FILE"
    
    # 更新配置文件
    local rules=$(jq ".inbounds |= map(select(.local_port != \"$local_port\"))" "$XRAY_CONFIG_FILE")
    echo "$rules" > "$XRAY_CONFIG_FILE"
    
    # 重启Xray服务
    systemctl restart xray
    
    echo -e "${GREEN}Xray转发规则删除成功${NC}"
}

# 列出所有转发规则
list_forwards() {
    echo -e "\n${CYAN}iptables转发规则:${NC}"
    if [ -f "$IPTABLES_CONFIG_FILE" ]; then
        jq -r '.[] | "本地端口: \(.local_port) → \(.target_address):\(.target_port) [\(.protocol)]"' "$IPTABLES_CONFIG_FILE"
    fi
    
    echo -e "\n${CYAN}Xray转发规则:${NC}"
    if [ -f "$XRAY_CONFIG_FILE" ]; then
        jq -r '.inbounds[] | "本地端口: \(.local_port) → \(.target_address):\(.target_port) [\(.protocol)]"' "$XRAY_CONFIG_FILE"
    fi
}

# 添加转发规则
add_forward() {
    echo -e "\n${YELLOW}=== 添加转发规则 ===${NC}"
    echo -e "1. iptables转发"
    echo -e "2. Xray转发"
    echo -e "3. 返回主菜单"
    
    read -p "请选择转发类型 [1-3]: " choice
    case $choice in
        1|2)
            read -p "请输入本地端口: " local_port
            read -p "请输入目标地址: " target_address
            read -p "请输入目标端口: " target_port
            read -p "请输入协议 (默认tcp): " protocol
            protocol=${protocol:-tcp}
            
            if [ $choice -eq 1 ]; then
                add_iptables_forward "$local_port" "$target_address" "$target_port" "$protocol"
            else
                add_xray_forward "$local_port" "$target_address" "$target_port" "$protocol"
            fi
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
}

# 删除转发规则
delete_forward() {
    echo -e "\n${YELLOW}=== 删除转发规则 ===${NC}"
    
    # 列出所有规则
    list_forwards
    
    echo -e "\n1. 删除iptables规则"
    echo -e "2. 删除Xray规则"
    echo -e "3. 返回主菜单"
    
    read -p "请选择要删除的规则类型 [1-3]: " choice
    case $choice in
        1)
            read -p "请输入要删除的本地端口: " local_port
            read -p "请输入目标地址: " target_address
            read -p "请输入目标端口: " target_port
            read -p "请输入协议 (默认tcp): " protocol
            protocol=${protocol:-tcp}
            delete_iptables_forward "$local_port" "$target_address" "$target_port" "$protocol"
            ;;
        2)
            read -p "请输入要删除的本地端口: " local_port
            delete_xray_forward "$local_port"
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${YELLOW}=== 端口转发管理工具 ===${NC}"
        echo -e "1. 添加转发规则"
        echo -e "2. 删除转发规则"
        echo -e "3. 查看所有规则"
        echo -e "4. 退出"
        
        read -p "请选择操作 [1-4]: " choice
        case $choice in
            1)
                add_forward
                ;;
            2)
                delete_forward
                ;;
            3)
                list_forwards
                ;;
            4)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}用法:${NC}"
    echo -e "  $0 [命令] [参数...]"
    echo
    echo -e "${CYAN}命令:${NC}"
    echo -e "  add [local_port] [remote_addr] [remote_port] [protocol]  添加转发规则"
    echo -e "  delete [local_port]                                      删除转发规则"
    echo -e "  list                                                     显示所有规则"
    echo -e "  show [local_port]                                        显示特定端口规则"
    echo -e "  clear                                                    清除所有规则"
    echo
    echo -e "${CYAN}示例:${NC}"
    echo -e "  $0 add 80 192.168.1.100 8080 tcp     # 添加TCP端口转发"
    echo -e "  $0 add 53 8.8.8.8 53 udp             # 添加UDP端口转发"
    echo -e "  $0 delete 80                          # 删除端口80的转发"
    echo -e "  $0 list                               # 显示所有转发规则"
    echo -e "  $0 clear                              # 清除所有转发规则"
}

# 快速添加转发规则
quick_add() {
    if [ $# -lt 3 ]; then
        echo -e "${RED}错误: 参数不足${NC}"
        echo -e "用法: $0 add [local_port] [remote_addr] [remote_port] [protocol]"
        return 1
    fi
    
    local local_port=$1
    local target_address=$2
    local target_port=$3
    local protocol=${4:-tcp}
    
    # 验证端口号
    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || ! [[ "$target_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口必须是数字${NC}"
        return 1
    fi
    
    # 验证协议
    if [[ "$protocol" != "tcp" ]] && [[ "$protocol" != "udp" ]]; then
        echo -e "${RED}错误: 协议必须是 tcp 或 udp${NC}"
        return 1
    fi
    
    add_iptables_forward "$local_port" "$target_address" "$target_port" "$protocol"
}

# 快速删除转发规则
quick_delete() {
    if [ $# -lt 1 ]; then
        echo -e "${RED}错误: 请指定要删除的端口${NC}"
        echo -e "用法: $0 delete [local_port]"
        return 1
    fi
    
    local local_port=$1
    
    # 查找并删除对应的规则
    local found=false
    if [ -f "$IPTABLES_CONFIG_FILE" ]; then
        while read -r rule; do
            local rule_port=$(echo "$rule" | jq -r '.local_port')
            if [ "$rule_port" = "$local_port" ]; then
                local target_address=$(echo "$rule" | jq -r '.target_address')
                local target_port=$(echo "$rule" | jq -r '.target_port')
                local protocol=$(echo "$rule" | jq -r '.protocol')
                delete_iptables_forward "$local_port" "$target_address" "$target_port" "$protocol"
                found=true
                break
            fi
        done < <(jq -c '.[]' "$IPTABLES_CONFIG_FILE")
    fi
    
    if [ -f "$XRAY_CONFIG_FILE" ]; then
        if jq -e ".inbounds[] | select(.port == $local_port)" "$XRAY_CONFIG_FILE" >/dev/null; then
            delete_xray_forward "$local_port"
            found=true
        fi
    fi
    
    if [ "$found" = false ]; then
        echo -e "${RED}错误: 未找到端口 $local_port 的转发规则${NC}"
        return 1
    fi
}

# 快速显示特定端口规则
quick_show() {
    if [ $# -lt 1 ]; then
        echo -e "${RED}错误: 请指定要显示的端口${NC}"
        echo -e "用法: $0 show [local_port]"
        return 1
    fi
    
    local local_port=$1
    local found=false
    
    echo -e "${CYAN}端口 $local_port 的转发规则:${NC}"
    
    if [ -f "$IPTABLES_CONFIG_FILE" ]; then
        while read -r rule; do
            local rule_port=$(echo "$rule" | jq -r '.local_port')
            if [ "$rule_port" = "$local_port" ]; then
                local target_address=$(echo "$rule" | jq -r '.target_address')
                local target_port=$(echo "$rule" | jq -r '.target_port')
                local protocol=$(echo "$rule" | jq -r '.protocol')
                echo -e "iptables转发: ${GREEN}$local_port${NC} -> ${GREEN}$target_address:$target_port${NC} (${GREEN}$protocol${NC})"
                found=true
            fi
        done < <(jq -c '.[]' "$IPTABLES_CONFIG_FILE")
    fi
    
    if [ -f "$XRAY_CONFIG_FILE" ]; then
        if jq -e ".inbounds[] | select(.port == $local_port)" "$XRAY_CONFIG_FILE" >/dev/null; then
            local target_address=$(jq -r ".inbounds[] | select(.port == $local_port) | .settings.vnext[0].address" "$XRAY_CONFIG_FILE")
            local target_port=$(jq -r ".inbounds[] | select(.port == $local_port) | .settings.vnext[0].port" "$XRAY_CONFIG_FILE")
            local protocol=$(jq -r ".inbounds[] | select(.port == $local_port) | .protocol" "$XRAY_CONFIG_FILE")
            echo -e "Xray转发: ${GREEN}$local_port${NC} -> ${GREEN}$target_address:$target_port${NC} (${GREEN}$protocol${NC})"
            found=true
        fi
    fi
    
    if [ "$found" = false ]; then
        echo -e "${RED}未找到端口 $local_port 的转发规则${NC}"
        return 1
    fi
}

# 清除所有规则
clear_all() {
    echo -e "${YELLOW}警告: 即将清除所有转发规则${NC}"
    read -p "是否继续？[y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 清除iptables规则
        iptables -t nat -F PREROUTING
        iptables -t nat -F POSTROUTING
        
        # 清除配置文件
        echo '[]' > "$IPTABLES_CONFIG_FILE"
        echo '{"inbounds":[]}' > "$XRAY_CONFIG_FILE"
        echo '{"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}' > "$XRAY_SYSTEM_CONFIG_FILE"
        
        # 重启Xray服务
        systemctl restart xray
        
        # 保存iptables规则
        save_iptables_rules
        
        echo -e "${GREEN}所有转发规则已清除${NC}"
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
}

# 处理命令行参数
handle_args() {
    case $1 in
        add)
            shift
            quick_add "$@"
            ;;
        delete)
            shift
            quick_delete "$@"
            ;;
        list)
            list_forwards
            ;;
        show)
            shift
            quick_show "$@"
            ;;
        clear)
            clear_all
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            if [ -n "$1" ]; then
                echo -e "${RED}错误: 未知命令 '$1'${NC}"
                show_help
                exit 1
            fi
            main_menu
            ;;
    esac
}

# 创建ipfw快捷命令
create_ipfw_command() {
    echo -e "${YELLOW}正在创建ipfw快捷命令...${NC}"
    
    # 获取脚本的绝对路径
    SCRIPT_PATH=$(readlink -f "$0")
    
    # 创建快捷命令
    cat > /usr/local/bin/ipfw << EOF
#!/bin/bash
$SCRIPT_PATH "\$@"
EOF
    
    # 设置执行权限
    chmod +x /usr/local/bin/ipfw
    
    echo -e "${GREEN}ipfw快捷命令创建成功${NC}"
    echo -e "现在可以直接使用 ${CYAN}ipfw${NC} 命令，例如："
    echo -e "  ${CYAN}ipfw add 80 192.168.1.100 8080${NC}"
    echo -e "  ${CYAN}ipfw list${NC}"
}

# 检查并删除旧的快捷命令
check_and_remove_old_command() {
    if [ -f /usr/local/bin/forward ]; then
        echo -e "${YELLOW}检测到旧的forward命令，正在删除...${NC}"
        rm -f /usr/local/bin/forward
    fi
}

# 主程序
check_root
detect_os
check_dependencies
init_config_dirs
check_system_settings
check_iptables_env
check_xray_env

# 创建ipfw快捷命令
check_and_remove_old_command
create_ipfw_command

# 处理命令行参数
handle_args "$@"
