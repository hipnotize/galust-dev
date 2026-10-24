---
title: "Backing up a Kubernetes cluster whose nodes can't reach anything"
date: 2026-10-24
description: "Running the Velero server outside the cluster, with a local S3 store, when the nodes have no internet access."
tags: ["kubernetes", "velero", "disaster-recovery"]
---

In October 2026 our cloud provider lost two of its three availability zones within a few days. The production cluster was still there, and its API server answered over VPN, but the surviving worker nodes had no internet access: the NAT gateway lived in a dead zone. The provider's object storage was read-only.

We needed a full backup of the cluster before deciding where to restore it. The usual way is to install Velero into the cluster, but that was impossible here: nodes couldn't pull the Velero image, and they couldn't reach any object storage to write to.

The trick that saved the day is simple. **Velero is a controller that talks to the API server. It doesn't have to run inside the cluster.**

## The plan

- The cluster gets only API objects: Velero CRDs, a namespace and a service account. No pods.
- The Velero server runs in Docker on a laptop that can reach the API server.
- The backup goes to an S3-compatible store on the same laptop.
- Volume data is copied separately, because file-system backups need the node agent, and the node agent would need the network the nodes didn't have.

## 1. API objects in the cluster

```bash
velero install --crds-only --dry-run -o yaml | kubectl apply -f -
kubectl create namespace velero
kubectl -n velero create serviceaccount velero
kubectl create clusterrolebinding velero-external \
  --clusterrole=cluster-admin --serviceaccount=velero:velero
```

Then a kubeconfig for that service account, so the server doesn't run with your personal credentials:

```bash
kubectl config view --minify --raw > velero.kubeconfig
TOKEN=$(kubectl -n velero create token velero --duration=12h)
kubectl --kubeconfig velero.kubeconfig config set-credentials velero --token="$TOKEN"
kubectl --kubeconfig velero.kubeconfig config set-context --current --user=velero
```

## 2. A local S3 store

I used SeaweedFS because the MinIO images were no longer available to pull. Any S3-compatible server works.

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

## 3. The storage location

The server reaches the store as `s3:8333` inside the Docker network. The `velero` CLI on the laptop needs `localhost:8333`, which is what `publicUrl` is for.

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

## 4. The Velero server in Docker

Inside a cluster, plugins are copied into the server pod by init containers. Outside, copy the plugin binary out of its image yourself:

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

kubectl -n velero get backupstoragelocation   # PHASE should become Available
```

## 5. The backup

```bash
velero backup create full-$(date +%F) \
  --include-cluster-resources=true --snapshot-volumes=false --wait
velero backup describe full-$(date +%F) --details
```

Our full backup of 72 namespaces — 10,466 objects — took about two minutes and finished with zero errors and zero warnings. I also kept a plain YAML dump of every resource type as a second, tool-independent copy and compared the object counts.

## What Velero didn't cover

**Volume data.** Without the node agent there are no file-system backups, so each stateful service got its own method, preferably a native one: a Raft snapshot for Vault, a fresh RDB file for Redis, data directories for RabbitMQ and Redpanda. Everything was streamed out with `kubectl exec ... tar`, checked with `gzip -t`, and saved with a sha256 sum next to it.

**Images.** If the registry dies with the cloud, a restored cluster has nothing to run. While the provider's registry still answered, a small script over the Registry HTTP API copied the manifests and layers of all 123 production images. Layers are shared between images, so deduplicating by digest brought 38 GB down to 19.7 GB.

## Lessons

- **Velero runs wherever the API server is reachable.** The cluster only needs its CRDs and a service account.
- **The backup contains every Secret in the cluster.** Treat the bucket and every copy of it as secret material.
- **Objects without data are half a backup.** Plan native dumps for stateful services before you need them.
- **Write down what you did as you go.** At 3 a.m. the runbook you wrote two hours earlier is the most useful document you have.

The restore deserves its own post: bringing 125 services back at zero replicas with Velero resource modifiers, so nothing started talking to a database that still pointed at the dead cloud.
