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
| OpenBao | Централизованное хранилище секретов (KV v2, AppRole) |
| swarm-external-secrets | Docker Secrets plugin для получения секретов из OpenBao |

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
                                               |
                                        External Secrets Plugin
                                               |
                                    OpenBao LXC 115 (via NPM)
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
| 115 | OpenBao | Debian 13 | 1 | 384 MiB (первоначально) | 4 GiB |

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
- **OpenBao** — хранилище секретов с KV v2 и машинной аутентификацией AppRole.

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

### 1.4. Подключение OpenTofu к Proxmox

## 2. Настройка OpenTofu

Перейти в директорию:

```bash
cd opentofu
```

Создать локальный файл переменных:

```bash
touch terraform.tfvars
```

В текущей конфигурации используется SSH-публичный ключ для Cloud-Init + адрес и токен proxmox:

```hcl
ssh_public_key   = "<your_public_key_here>"
proxmox_endpoint = "<your_proxmox_endpoint_here>"
proxmox_token    = "<your_proxmox_token_here>"
```

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

## 5. OpenBao и Docker Swarm Secrets

### 5.1. Архитектура и состояние

OpenBao развёрнут в LXC `openbao-01` (VMID `115`, Debian 13). Контейнер создаётся OpenTofu, а установка и конфигурация OpenBao выполняются ролью Ansible `openbao`.

- OpenBao: версия `2.7.1` на момент первоначальной настройки.
- Внутренний API: `http://127.0.0.1:8200` внутри LXC.
- Хранилище: integrated storage (Raft), `/var/lib/openbao/raft`.
- Инициализация: 3 unseal key shares, порог 2.
- KV v2: mount `secret/`, тестовый секрет `secret/apps/test` с полем `message`.
- Авторизация Swarm: AppRole `swarm`, policy `swarm-read` (read на `secret/data/apps/*`).
- Docker Swarm: сторонний plugin `swarm-external-secrets:latest`, получение тестового секрета проверено.

### 5.2. Provisioning и установка OpenBao

Из корня репозитория:

```bash
cd opentofu
tofu plan
tofu apply
```

Убедиться, что новый LXC доступен по SSH. Для Debian 13 LXC используется `root` с SSH-ключом; `sudo` внутри контейнера не требуется. Для доступа нужно добавить описание хоста в ssh config:

```
Host openbao-01
    HostName <your_lxc_ip>
    User root
    IdentityFile ~/.ssh/<your_key>
    IdentitiesOnly yes
```

Выполнить с управляющего компьютера:

```bash
cd ansible
ansible-playbook playbooks/openbao.yml
```

Плейбук использует роль `roles/openbao/`: установка пакета из APT-репозитория OpenBao, шаблон `/etc/openbao/openbao.hcl`, systemd unit и запуск сервиса.

Проверка **внутри LXC**:

```bash
systemctl status openbao
journalctl -u openbao -n 100 --no-pager
export BAO_ADDR=http://127.0.0.1:8200
bao status
```

Снаружи проверить TLS и доступность по домену, заведенному в adguard home + TLS proxy в nginx proxy manager:

```bash
curl -fsS https://<your_openbao_domain>/v1/sys/health
```

Для активного и распечатанного OpenBao обычно возвращается HTTP 200; запечатанный сервер возвращает другой код.

### 5.3. Инициализация и распечатывание (вручную, однократно)

**Не выполнять `bao operator init` повторно для уже инициализированного хранилища.** На новом пустом хранилище:

```bash
export BAO_ADDR=http://127.0.0.1:8200
bao operator init -key-shares=3 -key-threshold=2
```

Вывод содержит unseal keys и initial root token. Сохранить их в защищённом месте.

После инициализации и **после каждого перезапуска, когда OpenBao запечатан**:

```bash
bao operator unseal
bao operator unseal
bao status
```

Дважды вводятся **разные** unseal keys (порог 2 из 3). Если auto-unseal не настроен, это ручная операция. Для авторизации:

```bash
bao login
```

### 5.4. KV v2 и тестовый секрет (вручную)

Внутри LXC, после `bao login`:

```bash
bao secrets list -detailed
```

Если mount `secret/` ещё не существует:

```bash
bao secrets enable -path=secret -version=2 kv
```

Создать тестовое значение (не настоящий пароль):

```bash
bao kv put -mount=secret apps/test message=hello-from-openbao
bao kv get -mount=secret apps/test
```

KV v2 API-путь для чтения: `secret/data/apps/test`, в отличие от CLI-пути `secret/apps/test`.

### 5.5. Policy и AppRole для Swarm (вручную)

Создать локальный файл `swarm-read.hcl`:

```hcl
path "secret/data/apps/*" {
  capabilities = ["read"]
}
```

Применить:

```bash
bao policy write swarm-read swarm-read.hcl
bao auth list
```

Если `approle/` ещё нет:

```bash
bao auth enable approle
```

Создать роль:

```bash
bao write auth/approle/role/swarm \
  token_policies="swarm-read" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  token_no_default_policy=true \
  secret_id_ttl="0" \
  secret_id_num_uses=0
```

Получить Role ID и Secret ID:

```bash
bao read -field=role_id auth/approle/role/swarm/role-id
bao write -field=secret_id -f auth/approle/role/swarm/secret-id
```

Secret ID не имеет срока действия и лимита использований в текущем тестовом варианте. Он должен храниться как пароль; позже требуется спланировать ротацию и ограничить доступ. Policy `swarm-read` разрешает чтение **всех** секретов под `apps/*`

### 5.6. Ansible Vault и inventory (вручную)

Роль `swarm_secrets` требует переменных `swarm_secrets_openbao_role_id` и `swarm_secrets_openbao_secret_id`.

Пример расположения:

```text
ansible/
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       └── docker_swarm_managers/
│           ├── main.yml
│           └── vault.yml
├── playbooks/
│   ├── openbao.yml
│   └── swarm-secrets.yml
└── roles/
    ├── openbao/
    └── swarm_secrets/
```

В `inventory/group_vars/docker_swarm_managers/main.yml`:

```yaml
swarm_secrets_openbao_role_id: "REPLACE_WITH_ROLE_ID"
swarm_secrets_openbao_secret_id: "{{ vault_swarm_openbao_secret_id }}"
```

Создать зашифрованный файл:

```bash
cd ansible
ansible-vault create inventory/group_vars/docker_swarm_managers/vault.yml
```

Его **расшифрованное** содержимое:

```yaml
vault_swarm_openbao_secret_id: "REPLACE_WITH_SECRET_ID"
```

Зашифрованный файл допустимо хранить в Git, пароль Ansible Vault — нет. Не хранить Secret ID в незашифрованных переменных, Compose или коммитах.

Проверить, что хост действительно входит в группу `docker_swarm_managers`:

```bash
ansible-inventory --graph
```

Проверить только **факт наличия** переменной, без вывода её значения:

```bash
ansible docker-swarm-01 -m ansible.builtin.debug \
  -a 'msg={{ swarm_secrets_openbao_role_id is defined }}' \
  --ask-vault-pass
```

Если Ansible сообщает `swarm_secrets_openbao_role_id is undefined`, проверить имя группы, путь `group_vars` и используемый inventory.

### 5.7. Установка Docker Secrets plugin через Ansible

Роль: `roles/swarm_secrets/`, playbook: `playbooks/swarm-secrets.yml`. Запускать с управляющего компьютера:

```bash
cd ansible
ansible-playbook playbooks/swarm-secrets.yml --ask-vault-pass
```

Роль скачивает исходники `sugar-org/swarm-external-secrets`, собирает Docker plugin, настраивает OpenBao/AppRole и включает plugin на `docker-swarm-01`.

Проверка (на Swarm VM):

```bash
docker plugin ls
docker plugin inspect swarm-external-secrets:latest
```

Роль пока не считается полностью идемпотентной и безопасной для автоматической ротации. Если параметры включённого плагина изменились, их применение требует отдельного maintenance window: Docker plugin нужно отключать для изменения настроек. Не использовать принудительное отключение работающего плагина без анализа зависимостей. Ротация Secret ID, контроль drift и upgrade остаются задачами на будущее.

### 5.8. Проверка получения секрета из Swarm

Тестовый Compose-файл для отдельного stack:

```yaml
services:
  openbao-test:
    image: alpine:3.22
    command:
      - sh
      - -c
      - |
        test -s /run/secrets/test_message
        echo "OpenBao secret mounted successfully"
        sleep 3600
    secrets:
      - test_message
    deploy:
      replicas: 1

secrets:
  test_message:
    driver: swarm-external-secrets:latest
    labels:
      openbao_path: "apps/test"
      openbao_field: "message"
```

Этот формат был использован как ориентир для тестирования; при изменении версии плагина сверять labels с его документацией и рабочим Compose. Тест интеграции **успешно пройден**.

Развернуть с Swarm Manager в директории тестового Compose:

```bash
docker stack deploy -c compose.yml openbao-test
docker service ps openbao-test_openbao-test
docker service logs openbao-test_openbao-test
```

Ожидаем строку `OpenBao secret mounted successfully`. Настоящие секреты в логи не печатать.

### 5.9. Эксплуатация, безопасность и восстановление

- После перезапуска OpenBao проверить `bao status` и при необходимости вручную выполнить unseal.
- После перезапуска Swarm VM проверить `docker plugin ls` и наличие `/run/swarm-external-secrets`.
- Не передавать root token приложениям; использовать ограниченные AppRole.
- `no_log: true` скрывает параметры в выводе Ansible, но не исключает хранения credentials в конфигурации Docker plugin и их видимости администраторам Docker.
- Перед обновлением плагина оценить влияние на существующие Docker services и подготовить откат.
- Сохранить unseal keys и рабочий административный доступ вне сервера.
- Настроить Raft snapshots и регулярно проверять восстановление.
- При восстановлении из резервной копии **не** инициализировать поверх существующих данных.

## 6. GitOps и развёртывание приложений

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

## 7. Резервное копирование

Критически важные данные:

| Компонент | Что сохранять |
|---|---|
| Proxmox | Конфигурация хоста, VM и LXC backups |
| OpenTofu | Актуальный state |
| PostgreSQL | Логические и/или физические резервные копии БД |
| Vaultwarden | База данных, вложения, конфигурация |
| Gitea | Репозитории, БД, конфигурация |
| OpenBao | Raft snapshots, конфигурация, отдельно сохранённые unseal keys и процедура восстановления |
| Ansible Vault | Зашифрованные файлы и отдельно сохранённый пароль Vault |

Рекомендуется следовать правилу **3-2-1**:

- Три копии важных данных, включая рабочую.
- Два разных типа носителей или независимых места хранения.
- Одна копия вне основного сервера.

## 8. Дальнейшие планы

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
- [x] Развернуть OpenBao в LXC через OpenTofu и Ansible.
- [x] Настроить KV v2, тестовую policy и AppRole для Docker Swarm.
- [x] Подключить swarm-external-secrets и проверить тестовый секрет.
- [ ] Настроить резервное копирование Raft и проверить восстановление OpenBao.
- [ ] Довести роль swarm_secrets до проверенной идемпотентности и безопасной ротации credentials.
- [ ] Разделить политики доступа к секретам по приложениям.
- [ ] Перенести реальные секреты приложений в OpenBao.
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
