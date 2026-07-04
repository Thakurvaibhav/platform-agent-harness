# Network Policy and Cilium Learnings

Fleet NetworkPolicy strategy, self-managed Cilium (GKE + EKS), Istio-ambient coexistence, FQDN egress.

See also: `learnings-operators.md`

## Fleet substrate and provider facts

1. **GKE Dataplane V2 cannot be enabled on existing clusters** -- authoritative GCP docs state it can only be enabled at cluster creation time. Managed-Cilium fleet standard would require cluster replacement/blue-green. If replacement is out of scope, self-managed Cilium on existing GKE clusters is the only viable path.

2. **GKE self-managed Cilium has two modes; the tidy first-party one IS the full-takeover one**: Mode B (official GKE install section) = `gke.enabled=true, ipam.mode=kubernetes, routingMode=native, nodeinit.{reconfigureKubelet,removeCbrBridge}=true` -- preserves GKE-style PodCIDR allocation but takes over the CNI datapath and mutates kubelet/node state. Mode A (generic-veth chaining) preserves existing netd IPAM/routing but is documented only generically (not as a supported GKE integration) and has no persistence remedy when GKE node reboot/upgrade reinstates the default CNI (the warning is on `/en/stable/installation/taints/`, NOT the chaining page). Key insight: "B is better documented" and "B does the dataplane takeover" are the SAME fact -- its NodeInit DaemonSet solves the reboot problem precisely because it owns the CNI.

3. **EKS Cilium chaining capabilities and limits**: AWS VPC CNI keeps ENI/IPAM/pod interface + base routing; Cilium attaches eBPF after pod networking for L3/L4 policy/LB/observability (`cni.chainingMode=aws-cni, cni.exclusive=false, enableIPv4Masquerade=false, routingMode=native`). Official docs warn advanced features are limited in chaining, especially L7 policy/proxy redirects; transparent encryption is unsupported (cilium#15596). Existing pods must be RESTARTED after enabling chaining before Cilium policy applies. The AWS-managed VPC CNI add-on can overwrite daemonset fields on update cycles -- use add-on `configurationValues` for aws-node settings, keep AWS VPC CNI's own NP enforcement disabled when Cilium owns policy.

## Istio-ambient coexistence

4. **Cilium + Istio-ambient + kube-proxy + autoscaler coexistence facts** (Cilium v1.17+): (1) KEEP kube-proxy, `kubeProxyReplacement=false` -- Cilium-Istio integration requires `socketLB.hostNamespaceOnly=true` if KPR is on, else Cilium socket-LB rewrites connections inside the pod socket BEFORE ztunnel redirection sees them, breaking ambient. (2) `cni.exclusive=false` so Cilium doesn't remove the Istio CNI chained plugin. (3) No Cilium L7 on ambient workloads -- Cilium HTTP proxy + Istio mTLS = split-brain connection failures. (4) CRITICAL: ANY NetworkPolicy on an ambient-enrolled pod MUST allow TCP/15008 (HBONE) or it severs ztunnel tunnel traffic. (5) agent-not-ready taint applies at node-CREATE time only; existing clusters need new born-tainted node pools + cordon/drain/migrate; taint key MUST start with `ignore-taint.cluster-autoscaler.kubernetes.io/` or autoscaler refuses scale-up. (6) Policy Audit Mode allows traffic and logs would-drops (`hubble observe -t policy-verdict`); per-endpoint via `cilium-dbg endpoint config PolicyAuditMode=Enabled`; RESETS on cilium pod restart; NOT recommended for production steady-state; distinct from `enable-policy=never` (no enforce AND no verdicts). (7) Tetragon+Cilium dual-eBPF same-node is vendor-aligned but NOT conformance-documented; combined kernel/BTF floor unpinned -- validate in pilot.

5. **Policy-plane boundary with ambient**: For ambient-enrolled mTLS traffic, Kubernetes/Cilium NetworkPolicy still applies to the encrypted L4 HBONE tunnel entering/leaving Istio-managed pods, but Cilium has NO visibility into actual source/destination workload identity or L7. Therefore: Cilium/K8s NP owns pod selection, non-mesh/plaintext ingress, health-probe/link-local exceptions, infra boundaries, and coarse default-deny; Istio AuthorizationPolicy owns service-to-service identity/L4 and ALL L7 for ambient workloads. Cilium L7 policy requires removing the workload from ambient.

## FQDN egress

6. **`toFQDNs` / FQDN deny REQUIRES `l7Proxy=true`** (cilium#7109): the in-agent DNS proxy is gated by the L7 proxy flag -- FQDN policy is silently ineffective with `l7Proxy=false`. Tension: ambient coexistence posture is "no Cilium L7 on ambient workloads," but `l7Proxy` is a GLOBAL agent flag. Non-ambient workloads on dedicated pools CAN use FQDN deny (the DNS proxy runs in the Cilium agent, not in the workload), but squaring global-on with ambient-off needs per-pool design.

7. **FQDN egress default-deny landscape**: Solo Enterprise for Istio ztunnel-native L4 egress matches CIDR only (not FQDN), and CIDR-deny has the same churning-anycast-IP problem as IP allowlists. FQDN/hostname egress in Istio ambient requires the L7 waypoint egress gateway (extra proxy hop) and wildcard hostnames are unsupported. NET: Cilium `toFQDNs` (with `l7Proxy=true`) is the cleanest FQDN-deny primitive for Kubernetes.

## Principles

8. **Failure MODE matters as much as steady-state coverage**: A VPC firewall is fail-CLOSED (cloud fabric, no fail-open window); a node-local CNI policy (Cilium/Calico) is fail-OPEN during node lifecycle (agent not yet running). For untrusted-egress workloads, replacing a firewall with a CNI at equal rule coverage is a failure-mode REGRESSION. Keep the fail-closed backstop until replacement proves zero fail-open window.

9. **Cilium+Istio+ambient adoption has THREE stacked maturity layers -- don't launder L1 evidence as L3 proof**: L1 Cilium+Istio coexistence (sidecar era) = well-trodden. L2 Cilium+ambient/ztunnel specifically = thin but documented. L3 = Cilium primary CNI via IPAM takeover on existing non-DPv2 clusters + ztunnel + Tetragon (triple eBPF) = near-pioneering, no public reference; native Cilium-ztunnel datapath integration is an open upstream epic at low completion. General form: external evidence for layer N does not validate layer N+1.

## Tooling gotchas

10. **Cilium docs URLs move frequently**: A clean 404 usually means the content moved sections (the standalone GKE install page is gone; GKE flags now live inside the generic Helm install page). The node-reboot warning is on `/installation/taints/`, not the chaining page. Policy Audit Mode is on `/security/policy-creation/`, not policy/intro. When a doc 404s, search docs.cilium.io before concluding the feature is gone.
