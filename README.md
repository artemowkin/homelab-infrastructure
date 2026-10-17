# Homelab Infrastructure

Infrastructure as Code для домашней лаборатории на базе **Proxmox VE**, **OpenTofu**, **Ansible** и **Docker Swarm**.

Репозиторий содержит декларативное описание виртуальных машин, LXC-контейнеров, конфигурации Docker Swarm и инфраструктурных сервисов.

## Архитектура

| Компонент | Назначение |
|---|---|
| Proxmox VE | Гипервизор, управление LXC и VM |
| OpenTofu | Provisioning виртуальных машин и LXC |
| Ansible | Настройка ОС, Docker и инфраструктурных сервисов |
| Docker Swarm | Оркестрация контейнерных приложений |
| Portainer CE | Управление Docker Swarm и GitOps-развёртывания |
| Gitea | Git-репозитории инфраструктуры и приложений |
| Nginx Proxy Manager | Reverse proxy и TLS для локальных сервисов |
| InfluxDB + Grafana | Сбор, хранение и визуализация метрик |

### Схема инфраструктуры

```text
                        Home LAN
                     192.168.0.0/24
                            |
                       Proxmox VE
                            |
             +--------------+--------------+
             |              |              |
         LXC Containers   Virtual Machines |
             |              |              |
    +--------+-------+      +--------------+
    |        |       |      |
  Gitea   NPM    Monitoring |
    |                    +--+-------------------+
    |                    |                      |
    |              infra-postgresql        docker-swarm-01
    |                 VM 113                  VM 120
    |                                          |
    |                                     Docker Swarm
    |                                          |
    +---- GitOps ------------------------> Portainer
                                               |
                                           Swarm Stacks
```

## Текущие ресурсы

### LXC-контейнеры

Все контейнеры работают на Proxmox, используют bridge `vmbr0` и хранилище `local-lvm`.


| VMID | Сервис | ОС | CPU | RAM | Диск |
|---|---|---|---|---|---|
| 100 | Vaultwarden | Debian | 1 | 512 MiB | 8 GiB |
| 101 | Vikunja | Debian | 1 | 512 MiB | 4 GiB |
| 102 | AdGuard Home | Debian | 1 | 256 MiB | 4 GiB |
| 103 | Nginx Proxy Manager | Debian | 1 | 512 MiB | 4 GiB |
| 104 | WireGuard | Debian | 1 | 256 MiB | 2 GiB |
| 105 | Uptime Kuma | Debian | 1 | 512 MiB | 8 GiB |
| 106 | Gotify | Debian | 1 | 256 MiB | 8 GiB |
| 109 | InfluxDB | Debian | 2 | 1024 MiB | 8 GiB |
| 110 | Grafana | Alpine | 1 | 512 MiB | 2 GiB |
| 112 | Gitea | Debian | 1 | 512 MiB | 10 GiB |
| 114 | Gitea Runner | Debian | 1 | 512 MiB | 8 GiB |

Назначение основных сервисов:

- **Vaultwarden** — собственный сервер паролей, совместимый с клиентами Bitwarden.
- **Vikunja** — управление задачами.
- **AdGuard Home** — локальный DNS и фильтрация рекламы.
- **Nginx Proxy Manager** — маршрутизация HTTP(S)-трафика и управление TLS-сертификатами.
- **WireGuard** — VPN-доступ в домашнюю сеть.
- **Uptime Kuma** — мониторинг доступности сервисов.
- **Gotify** — push-уведомления.
- **InfluxDB** — хранение временных рядов и метрик.
- **Grafana** — визуализация метрик.
- **Gitea** — собственный Git-сервер.
- **Gitea Runner** — выполнение CI/CD jobs.

Контейнеры являются непривилегированными (`unprivileged`) и запускаются автоматически при старте Proxmox.

Некоторые контейнеры имеют дополнительные настройки, например `nesting`, `keyctl` или проброс `/dev/net/tun` для WireGuard.

### Виртуальные машины

| VMID | Имя | ОС | CPU | RAM | Назначение |
|---|---|---|---|---|---|
| 113 | infra-postgresql | Debian 13 | 1 | 1024 MiB | PostgreSQL для инфраструктурных сервисов |
| 120 | docker-swarm-01 | Debian 13 | 2 | 2048 MiB | Docker Swarm Manager |

`infra-postgresql` — существующая виртуальная машина, импортированная под управление OpenTofu. Её диск и данные необходимо сохранять при изменениях инфраструктуры.

`docker-swarm-01` создаётся из Debian 13 Cloud Image с использованием Cloud-Init.

IP-адреса получаются по DHCP и могут измениться. Для стабильной инфраструктуры рекомендуется закрепить их на роутере через DHCP reservation.

### Docker Swarm

На текущий момент используется один Swarm Manager:

```text
docker-swarm-01
```

Он выполняет роли Manager и Worker.

## Требования

Для управления инфраструктурой необходимы:

- OpenTofu.
- Ansible.
- OpenSSH Client.
- Доступ к Proxmox API.
- SSH-доступ к виртуальным машинам.
- Git.

## 1. Настройка Proxmox API

OpenTofu использует провайдер `bpg/proxmox` версии `0.116.0`.

Для управления ресурсами используется отдельный API Token, а не пароль пользователя `root`.

### 1.1. Создание API-пользователя

Подключиться к Proxmox по SSH:

```bash
ssh root@<PROXMOX_IP>
```

Создать пользователя:

```bash
pveum user add opentofu@pve \
  --comment "OpenTofu Infrastructure Automation"
```

Создать API-токен:

```bash
pveum user token add opentofu@pve homelab \
  --privsep 0
```

Будет создан токен:

```text
opentofu@pve!homelab
```

**Секрет токена показывается при создании. Его необходимо сохранить в безопасном месте.**

`--privsep 0` означает, что токен использует права пользователя `opentofu@pve`, а не отдельный набор ACL.

### 1.2. Создание ролей

Для ограничения прав OpenTofu используются отдельные роли.

#### Чтение инфраструктуры

```bash
pveum role add OpenTofuReadOnly \
  -privs "Sys.Audit VM.Audit Datastore.Audit"
```

#### Управление LXC

```bash
pveum role add OpenTofuLXC \
  -privs "VM.Audit VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network VM.Config.Options VM.Config.HWType VM.PowerMgmt"
```

#### Управление виртуальными машинами

```bash
pveum role add OpenTofuVM \
  -privs "VM.Allocate VM.Audit VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network VM.Config.Options VM.Config.HWType VM.Config.Cloudinit VM.PowerMgmt"
```

#### Управление шаблонами

```bash
pveum role add OpenTofuTemplates \
  -privs "Datastore.Audit Datastore.AllocateTemplate"
```

#### Выделение дискового пространства

```bash
pveum role add OpenTofuStorage \

  -privs "Datastore.Audit Datastore.AllocateSpace"
```

#### Использование сети

```bash

pveum role add OpenTofuNetwork \
  -privs "SDN.Use"
```

> Эти роли отражают текущий набор операций, но не гарантируют покрытие всех будущих ресурсов провайдера. При добавлении новых возможностей OpenTofu может потребоваться расширить ACL.

### 1.3. Назначение ACL

```bash
pveum aclmod / \
  -user opentofu@pve \
  -role OpenTofuReadOnly

pveum aclmod /vms \
  -user opentofu@pve \
  -role OpenTofuLXC

pveum aclmod /vms \
  -user opentofu@pve \
  -role OpenTofuVM

pveum aclmod /storage/local \
  -user opentofu@pve \
  -role OpenTofuTemplates

pveum aclmod /storage/local-lvm \
  -user opentofu@pve \
  -role OpenTofuStorage

pveum aclmod /sdn/zones/localnetwork/vmbr0 \
  -user opentofu@pve \
  -role OpenTofuNetwork
```

Проверить права:

```bash
pveum user permissions opentofu@pve
```

Проверить роли:

```bash
pveum role list
```

**Важное замечание:** текущая конфигурация использует отдельные роли для VM и LXC. При расширении инфраструктуры могут потребоваться дополнительные разрешения, например для создания LXC, настройки startup order или других параметров Proxmox.

Выдавать `Administrator` на весь Proxmox без необходимости не рекомендуется.

### 1.4. Подключение OpenTofu к Proxmox

На локальном компьютере необходимо определить переменные окружения:

```bash
export PROXMOX_VE_ENDPOINT="https://<PROXMOX_IP>:8006/"
export PROXMOX_VE_API_TOKEN="opentofu@pve!homelab=<TOKEN_SECRET>"
```

## 2. Настройка OpenTofu

Перейти в директорию:

```bash
cd opentofu
```

Создать локальный файл переменных:

```bash
touch terraform.tfvars
```

В текущей конфигурации используется SSH-публичный ключ для Cloud-Init:

```hcl
ssh_public_key = "ssh-ed25519 AAAA... user@host"
```

Приватный SSH-ключ в OpenTofu передавать не нужно.

### Инициализация

```bash
tofu init
```

### Проверка конфигурации

```bash
tofu fmt -recursive
tofu validate
```

### Просмотр изменений

```bash

tofu plan
```

### Применение

```bash
tofu apply
```

## 3. Настройка SSH

Ansible использует SSH для подключения к виртуальным машинам.

### 3.2. SSH Config

На управляющем компьютере отредактировать:

```bash

nvim ~/.ssh/config
```

Добавить:

```sshconfig
Host docker-swarm-01
    HostName <VM IP>
    User debian
    IdentityFile ~/.ssh/<key_name>
    IdentitiesOnly yes
```

Проверить подключение:

```bash
ssh docker-swarm-01
```

### 3.3. SSH Agent

Если SSH-ключ защищён passphrase:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/<key>
```

Проверить загруженные ключи:

```bash
ssh-add -l
```

## 4. Настройка Ansible

Перейти в директорию:

```bash
cd ansible
```

### Конфигурация Ansible

`ansible.cfg`:

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
interpreter_python = auto_silent
host_key_checking = True
retry_files_enabled = False
```

### Проверка inventory

```bash
ansible-inventory --graph
```

### Проверка подключения

```bash
ansible all -m ping
```

Ожидаемый результат:

```text
docker-swarm-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### Настройка Docker Swarm

```bash
ansible-playbook playbooks/docker-swarm.yml
```

Плейбук устанавливает Docker Engine и необходимые плагины, настраивает Docker daemon и инициализирует Swarm, если он ещё не создан.

### Развёртывание Portainer

```bash
ansible-playbook playbooks/portainer.yml
```

Portainer разворачивается как Docker Swarm stack.

## 5. GitOps и развёртывание приложений

Для развёртывания пользовательских приложений используется **Portainer CE с GitOps polling**.

Принцип работы:

```text
Gitea Repository
       |
       | git push
       v
Portainer GitOps Polling
       |
       | Detect changes
       v
Docker Stack Deploy
       |
       v
Docker Swarm Services
```

Приложения хранятся в отдельном Git-репозитории с Compose-файлами.

Пример:

```text
homelab-apps/
├── whoami/
│   └── compose.yml
├── backend/
│   └── compose.yml
└── frontend/

    └── compose.yml
```

Для подключения нового приложения:

1. Создать Compose-файл в Git-репозитории.
2. Создать stack в Portainer.
3. Выбрать развёртывание из Git Repository.
4. Указать URL репозитория, ветку и путь к Compose-файлу.
5. Включить GitOps updates с периодическим polling.

После этого изменения Compose-файла автоматически применяются Portainer.

### Пример Compose-файла

```yaml
services:
  app:
    image: registry.example.com/app:1.0.0
    deploy:
      replicas: 1
      update_config:
        parallelism: 1
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
```

Чтобы обновить приложение, достаточно изменить тег Docker-образа в Git и выполнить push.

Portainer обнаружит новый коммит и применит обновлённую конфигурацию.

**Ограничение:** Portainer не обнаруживает новые Compose-файлы автоматически. Каждый новый stack нужно зарегистрировать один раз вручную или через Portainer API.

Также Portainer GitOps не является полноценным аналогом Argo CD с непрерывным восстановлением любого drift.

## 7. Резервное копирование

Критически важные данные:

| Компонент | Что сохранять |
|---|---|
| Proxmox | Конфигурация хоста, VM и LXC backups |
| OpenTofu | Актуальный state |
| PostgreSQL | Логические и/или физические резервные копии БД |
| Vaultwarden | База данных, вложения, конфигурация |
| Gitea | Репозитории, БД, конфигурация |

Рекомендуется следовать правилу **3-2-1**:

- Три копии важных данных, включая рабочую.
- Два разных типа носителей или независимых места хранения.
- Одна копия вне основного сервера.

## 9. Дальнейшие планы

- [x] Перенести существующие LXC под управление OpenTofu.
- [x] Перенести PostgreSQL VM под управление OpenTofu.
- [x] Настроить Debian 13 Cloud Image.
- [x] Создать Docker Swarm VM через OpenTofu.
- [x] Автоматизировать установку Docker через Ansible.
- [x] Инициализировать Docker Swarm.
- [x] Развернуть Portainer CE.
- [x] Настроить GitOps-развёртывание приложений из Gitea.
- [ ] Настроить резервное копирование Proxmox, VM и LXC.
- [ ] Настроить резервное копирование OpenTofu state.
- [ ] Перенести OpenTofu state в защищённый remote backend.
- [ ] Настроить мониторинг Docker через node-exporter и cAdvisor.
- [ ] Подключить метрики Proxmox к InfluxDB и Grafana.
- [ ] Настроить доступ к Swarm-приложениям через Nginx Proxy Manager.
- [ ] Централизовать управление секретами.
- [ ] Автоматизировать регистрацию новых GitOps stacks через Portainer API.
- [ ] Настроить уведомления о сбоях через Gotify.
- [ ] Рассмотреть расширение Swarm на дополнительные ноды.

## Принципы управления инфраструктурой

1. Инфраструктура описывается декларативно.
2. Изменения Proxmox выполняются преимущественно через OpenTofu.
3. Конфигурация ОС и bootstrap выполняются через Ansible.
4. Приложения Docker Swarm разворачиваются через Portainer GitOps.
5. Секреты не хранятся в Git в открытом виде.
6. Перед применением OpenTofu всегда проверяется `tofu plan`.
7. Данные существующих сервисов должны сохраняться при изменениях инфраструктуры.
8. Любое критичное изменение должно иметь понятный сценарий отката или восстановления.
