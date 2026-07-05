---
title: Ztunnel Unmasked — the "long straw" mental model
source_url: https://jackma.com/2026/07/03/ztunnel-unmasked/
author: Jack Ma
date_added: 2026-07-04
tags: [istio, ambient, ztunnel, hbone, mtls, network-policy]
maturity: reference
applies_to: [istio, network-policy, k8s]
status: vetted
---

# Ztunnel Unmasked — the "long straw" mental model

**TL;DR:** ztunnel is a per-pod-scoped, identity-pinned userspace TCP proxy — one pod
per node that uses `setns()` to reach *into* each pod's netns while keeping the pod's
identity; node IPs never appear as HBONE endpoints.

## Key takeaways
- **Long-straw model:** ztunnel runs as a normal pod (own IP, not host-networked),
  enters each pod's network namespace via `setns()` to bind capture sockets locally.
  Needs `CAP_SYS_ADMIN`.
- **HBONE = HTTP/2 CONNECT**, not a VXLAN/Geneve overlay. Pod-IP→pod-IP on **15008**,
  mTLS-encrypted; the app port rides as the CONNECT authority. End-to-end the server
  sees the *client pod IP*, not the node IP.
- **Identity-scoped connection pooling:** `{src_identity, dst_identity, src_pod_IP, dst_pod_IP:15008}`.
- **Port map:** 15001 outbound capture · 15006 inbound plaintext · 15008 inbound HBONE (mTLS H2) · 15053 DNS (localhost).
- **Non-DNS UDP is NOT carried over HBONE** in the Istio 1.30 in-pod redirection model —
  rides plaintext via CNI.
- **HBONE requires NetworkPolicy allowing TCP 15008** pod-to-pod, or ambient traffic breaks.
- **Debug:** `nsenter -t <pod-pid> -n ss -lntp` (ztunnel sockets inside pod) ·
  `istioctl ztunnel-config workloads` · ztunnel access logs for identity+routing.

## How this applies to us
- If you run **ambient + fleet-wide STRICT mTLS**, the long-straw/`setns` framing
  corroborates and sharpens ztunnel netns/fwmark/tcpdump debugging.
- **Fleet NetworkPolicy (self-managed Cilium):** any policy you ship MUST allow
  **TCP 15008 pod-to-pod** or ambient HBONE silently breaks. This is a hard constraint on
  any ambient-mesh netpol rollout — reinforces the Istio-ambient coexistence guidance in
  `learnings-network-policy.md`.
- If any workload depends on **non-DNS UDP** under ambient, know it rides plaintext via CNI
  (not mTLS-protected) on Istio 1.30 — a STRICT-mode blind spot to check.

## Cross-links
- [[learnings-network-policy]] — NetworkPolicy must allow TCP 15008 for HBONE (Cilium fleet constraint)
- [[learnings-observability]] — alerting patterns for mesh dataplane health (e.g. ztunnel-down, HBONE reachability)
- Source: https://jackma.com/2026/07/03/ztunnel-unmasked/
