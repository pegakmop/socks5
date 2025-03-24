#!/bin/bash

# Определение цветовых кодов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Без цвета

# Проверка, установлен ли danted
if command -v danted &>/dev/null; then
    echo -e "${GREEN}Dante SOCKS5 сервер уже установлен.${NC}"
    echo -e "${CYAN}Выберите действие: (1) Перенастроить, (2) Удалить, (3) Выйти (введите 1, 2 или 3):${NC}"
    read choice
    case "$choice" in
        1)
            echo -e "${CYAN}Введите порт для SOCKS5 прокси (по умолчанию: 1080):${NC}"
            read port
            port=${port:-1080}
            ;;
        2)
            echo -e "${YELLOW}Удаление Dante SOCKS5...${NC}"
            sudo systemctl stop danted
            sudo systemctl disable danted
            sudo apt remove --purge dante-server -y
            sudo rm -f /etc/danted.conf /var/log/danted.log
            echo -e "${GREEN}Dante SOCKS5 сервер удален.${NC}"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}Выход.${NC}"
            exit 0
            ;;
    esac
else
    echo -e "${YELLOW}Dante SOCKS5 сервер не установлен.${NC}"
    echo -e "${CYAN}Введите порт для SOCKS5 прокси (по умолчанию: 1080):${NC}"
    read port
    port=${port:-1080}
fi

# Установка или перенастройка Dante
sudo apt update -y
sudo apt install dante-server curl -y
echo -e "${GREEN}Dante SOCKS5 установлен.${NC}"

# Создание файла логов
sudo touch /var/log/danted.log
sudo chown nobody:nogroup /var/log/danted.log

# Определение основного сетевого интерфейса
primary_interface=$(ip route | grep default | awk '{print $5}')
if [[ -z "$primary_interface" ]]; then
    echo -e "${RED}Ошибка: не удалось определить сетевой интерфейс.${NC}"
    exit 1
fi

# Создание конфигурационного файла
sudo bash -c "cat <<EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $port
external: $primary_interface
method: none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF"

# Настройка firewall
if sudo ufw status | grep -q "Status: active"; then
    if ! sudo ufw status | grep -q "$port/tcp"; then
        sudo ufw allow "$port/tcp"
    fi
fi

if ! sudo iptables -L | grep -q "tcp dpt:$port"; then
    sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
fi

# Перезапуск службы
sudo systemctl daemon-reload
sudo systemctl restart danted
sudo systemctl enable danted

# Проверка состояния службы
if systemctl is-active --quiet danted; then
    echo -e "${GREEN}SOCKS5 сервер запущен на порту $port.${NC}"
else
    echo -e "${RED}Ошибка: не удалось запустить сервер. Проверьте логи: /var/log/danted.log${NC}"
    exit 1
fi

# Проверка работы SOCKS5 прокси
echo -e "${CYAN}\nТестирование SOCKS5 прокси...${NC}"
proxy_ip=$(hostname -I | awk '{print $1}')
if curl -x socks5h://"$proxy_ip":"$port" https://ipinfo.io/; then
    echo -e "${GREEN}\nSOCKS5 прокси работает успешно.${NC}"
else
    echo -e "${RED}\nОшибка: проверка прокси не удалась.${NC}"
fi
