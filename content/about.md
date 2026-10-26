---
title: "About"
description: "Galust Arakelyan, DevOps engineer."
---

I'm Galust, a DevOps engineer. Right now I run production Kubernetes for a fintech lending group: managed Kubernetes in the cloud, VMware and our own hardware, plus all the stateful pieces that come with money — PostgreSQL, RabbitMQ, Redis, Redpanda and Vault.

A recent example: in October 2026 our cloud provider lost two of its three availability zones within a few days. Production went down, the surviving worker nodes had no internet access, and everything had to be pulled out and started somewhere else. I backed up the clusters with Velero running outside the cluster, saved the images and the state of Vault, Redis, RabbitMQ and Redpanda, and then restored them on new Kubernetes in our office within a day. The backup part is described in [this post](/blog/velero-without-internet/).

## How I work

- **Evidence before guesses.** Audit logs, Helm history, log offsets and metrics usually answer "who did this" and "where did the data go" faster than theories.
- **Dry run first.** Anything that touches production in bulk gets a dry run, check-and-set writes and a rollback log.
- **Write it down.** After an incident I leave a runbook, so the next person doesn't start from zero.

## Teaching

On the side I mentor DevOps students at ProstoDevops, an online school: code reviews, mock interviews and hands-on labs.

## Contact

I speak Russian, Armenian and English. The fastest way to reach me is [Telegram](https://t.me/thelastbroken); email works too: [galust.arakelyan25@gmail.com](mailto:galust.arakelyan25@gmail.com). My CV is [here](/cv/).
