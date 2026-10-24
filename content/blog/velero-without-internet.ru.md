---
title: "Как снять бэкап Kubernetes-кластера, когда ноды никуда не достучатся"
date: 2026-10-24
description: "Сервер Velero вне кластера и локальное S3-хранилище, когда у нод нет выхода в интернет."
tags: ["kubernetes", "velero", "disaster-recovery"]
---

В октябре 2026 года наш облачный провайдер за несколько дней потерял две из трёх зон доступности. Прод-кластер был на месте, и его API-сервер отвечал через VPN, но у оставшихся воркеров не было интернета: NAT-шлюз жил в мёртвой зоне. Объектное хранилище провайдера работало только на чтение.

Прежде чем решать, где восстанавливаться, нужна была полная копия кластера. Обычно Velero ставят прямо в кластер, но здесь это было невозможно: ноды не могли скачать образ Velero и не могли достучаться ни до какого хранилища, чтобы туда писать.

Выручила простая мысль. **Velero — это контроллер, который разговаривает с API-сервером. Ему не обязательно жить внутри кластера.**

## План

- В кластер попадают только API-объекты: CRD Velero, неймспейс и сервисный аккаунт. Никаких подов.
- Сервер Velero работает в Docker на ноутбуке, у которого есть доступ к API-серверу.
- Копия пишется в S3-совместимое хранилище на том же ноутбуке.
- Данные томов копируются отдельно: файловым бэкапам нужен node agent, а node agent'у нужна сеть, которой у нод не было.

## 1. API-объекты в кластере

```bash
velero install --crds-only --dry-run -o yaml | kubectl apply -f -
kubectl create namespace velero
kubectl -n velero create serviceaccount velero
kubectl create clusterrolebinding velero-external \
  --clusterrole=cluster-admin --serviceaccount=velero:velero
```

Дальше kubeconfig для этого сервисного аккаунта, чтобы сервер не работал под твоими личными правами:

```bash
kubectl config view --minify --raw > velero.kubeconfig
TOKEN=$(kubectl -n velero create token velero --duration=12h)
kubectl --kubeconfig velero.kubeconfig config set-credentials velero --token="$TOKEN"
kubectl --kubeconfig velero.kubeconfig config set-context --current --user=velero
```

## 2. Локальное S3-хранилище

Я взял SeaweedFS, потому что образы MinIO скачать уже было нельзя. Подойдёт любой S3-совместимый сервер.

```json
{
  "identities": [
    {
      "name": "velero",
      "credentials": [{ "accessKey": "velero", "secretKey": "change-me" }],
      "actions": ["Admin", "Read", "Write", "List", "Tagging"]
    }
  ]
}
```

```bash
docker network create velero-net
docker run -d --name s3 --network velero-net -p 8333:8333 \
  -v "$PWD/s3.json:/etc/seaweedfs/s3.json:ro" -v "$PWD/s3-data:/data" \
  chrislusf/seaweedfs server -dir=/data -s3 -s3.config=/etc/seaweedfs/s3.json

AWS_ACCESS_KEY_ID=velero AWS_SECRET_ACCESS_KEY=change-me \
  aws --endpoint-url http://localhost:8333 s3 mb s3://velero
```

## 3. Место хранения копий

Сервер видит хранилище как `s3:8333` внутри Docker-сети. CLI `velero` на ноутбуке ходит на `localhost:8333` — для этого и нужен `publicUrl`.

```yaml
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  default: true
  objectStorage:
    bucket: velero
  config:
    region: local
    s3ForcePathStyle: "true"
    s3Url: http://s3:8333
    publicUrl: http://localhost:8333
```

## 4. Сервер Velero в Docker

В кластере плагины копируются в под сервера init-контейнерами. Снаружи бинарник плагина нужно достать из образа самому:

```bash
docker create --name aws-plugin velero/velero-plugin-for-aws:v1.11.0
docker cp aws-plugin:/plugins ./plugins
docker rm aws-plugin

printf '[default]\naws_access_key_id=velero\naws_secret_access_key=change-me\n' > credentials-velero

docker run -d --name velero --network velero-net \
  -v "$PWD/velero.kubeconfig:/kubeconfig:ro" \
  -v "$PWD/plugins:/plugins:ro" \
  -v "$PWD/credentials-velero:/credentials/cloud:ro" \
  -e KUBECONFIG=/kubeconfig \
  -e AWS_SHARED_CREDENTIALS_FILE=/credentials/cloud \
  -e VELERO_NAMESPACE=velero \
  -e VELERO_SCRATCH_DIR=/tmp/scratch \
  velero/velero:v1.15.2 server

kubectl -n velero get backupstoragelocation   # PHASE должна стать Available
```

## 5. Копия

```bash
velero backup create full-$(date +%F) \
  --include-cluster-resources=true --snapshot-volumes=false --wait
velero backup describe full-$(date +%F) --details
```

Полная копия 72 неймспейсов — 10 466 объектов — заняла около двух минут и прошла без единой ошибки и предупреждения. Отдельно я сохранил обычный YAML-дамп всех типов ресурсов как вторую копию, не зависящую от инструмента, и сверил число объектов.

## Чего Velero не забрал

**Данные томов.** Без node agent файловых бэкапов нет, поэтому для каждого сервиса с состоянием нашёлся свой способ, по возможности родной: raft-снапшот для Vault, свежий RDB-файл для Redis, каталоги данных для RabbitMQ и Redpanda. Всё выгружалось через `kubectl exec ... tar`, проверялось `gzip -t` и сохранялось вместе с sha256-суммой.

**Образы.** Если реестр умрёт вместе с облаком, восстановленному кластеру будет нечего запускать. Пока реестр провайдера ещё отвечал, небольшой скрипт через Registry HTTP API скопировал манифесты и слои всех 123 прод-образов. Слои у образов общие, поэтому дедупликация по digest ужала 38 ГБ до 19,7 ГБ.

## Выводы

- **Velero работает везде, откуда виден API-сервер.** Кластеру нужны только его CRD и сервисный аккаунт.
- **В копии лежат все Secret'ы кластера.** Бакет и каждую его копию охраняй как секреты.
- **Объекты без данных — это половина бэкапа.** Родные дампы для сервисов с состоянием продумай заранее.
- **Записывай, что делаешь, по ходу.** В три часа ночи ранбук, написанный два часа назад, — самый полезный документ.

Восстановление заслуживает отдельной статьи: как 125 сервисов поднимали при нуле реплик через resource modifiers Velero, чтобы ничто не начало ходить в базу, которая ещё смотрела в мёртвое облако.
