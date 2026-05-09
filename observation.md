# Important Notes:

The importatn key technical points in the composer-2 paper [link here](https://arxiv.org/abs/2603.24477)

## Training Service

### The reason behind handling with distributed system

1. Decoupling training from inference and environment infrastructure naturally makes training more resilient to failures in these services;
2. During the training run, we saw many cases where these services hadpartial or full outages without failing the training job. To minimize the number of training job restarts, we use a reactive configuration system and support live code updates on a per- process level; when new code is deployed, existing actors are drained of in-flight requests  and transparently replaced.

### If CPU memory is Full we avoid RAY Object Store use Storage instead

1. We leverage the Ray object store to hold samples that are ready for consumption by train workers, which allows for natural spilling to local NVMe storage when nodes have insufficient CPU memory

### How weights stored and mid-flights updated happen on th flow ?

1. Every training step, we synchronize updated weights to the inference engine by uploading
   to a shared S3 bucket. To minimize transfer size, we use delta compression: each rank
   caches its previous upload and transmits only the diff against the new weights. Because RL
   updates are small, even with full-parameter training these diffs compress to a handful of
   gigabytes for the 1T-parameter model

### Storing snapshot in memory for rollouts failure

1. For rollout checkpointing, we rely on memory snapshots of the codebase environment state, so that
   upon recovery, we can pass the reconstructed codebase environment to verifiers.

### Storing processed group rollouts checkpoint in NFS

1. For group checkpointing, we write sequences with advantages tagged with policy versions to NFS;
   upon job restart, the scheduler considers these when determining whether to dispatch new
   work or simply load ready groups.

## Environment Service

### Triggering multiple pods in anyrun Cluster ?

1. Scheduling throughput is particularly important for the bursty nature of RL workloads. Each
   Anyrun cluster is capable of scheduling more than 500 pods per second while maintaining
   desired binpacking requirements. One challenge with a naive packing strategy is that the
   steady-state resource usage for a pod can be dramatically lower than its peak during startup
   and can also be bursty due to overcommits.
2. To solve this, we monitor and schedule with awareness of live readings of hardware pressure (CPU, memory, disk) along with more conventional scheduling heuristics.

### How tools are executed ?

1. We train with tools that are representative of the harness in the Cursor client. Each codebase
   environment starts with a shared tool library that can be invoked over RPC. Some tools like
   semantic search have external dependencies and are handled outside of the environment.

```json
//Example RPC tool call
{
   "method": "bash.run",
   "params": {
     "cmd": "cat <filePath>"
    }
}
```

* To support the full tool set available in the Cursor client, we maintain a shadow deployment
  of the Cursor backend that is used both during dataset preparation and rollouts. Sharing the
  production implementation in this way allows us to scale experiments and training safely
  while remaining faithful to the harness that Composer 2 will be deployed into.

### How Anyrun Cluster snapshots the agent patches/changes ?

1. Anyrun supports forking and snapshotting of full coding environments at both the filesys-
   tem and memory level. This unlocks useful capabilities during RL, such as mid-trajectory
   rollout checkpointing and post-rollout state capture for future introspection. When a pod fork is requested, we attempt to first schedule the fork onto the same node; if not feasible due to space constraints, we live-migrate pod state to a node with capacity.
2. we rely on memory snapshots of the codebase environment state, so that upon recovery, we can pass the reconstructed codebase environment to verifiers. For group checkpointing, we write sequences with advantages tagged with policy versions to NFS; upon job restart, the scheduler considers these when determining whether to dispatch new work or simply load ready groups.

### How the non-linear penalizing imrpove the efficiency of the model ?

1. To incentivize the model to produce solutions quickly on easy requests while allowing it to think longer on hard requests, we add a concave down and increasing nonlinear length penalty to the reward, Nonlinear penalties push the model to be quick on easy tasks and think more on hard tasks.

$$
C_{\text{length}}^{k,q}(x) =
\frac{(1 + kx)^{1-q} - 1}{k(1-q)}
$$

2. where k and q are hyperparameters which define the curvature of the penalty, and the input
   x is a weighted combination of thinking tokens, tool calling tokens, tool output tokens, final
   message tokens, number of tool calls, and number of turns of a rollout. The nonlinearity
   reflects that on easy tasks, achievable with only a few tool calls, every additional bit of effort
   is felt more acutely than in long-horizon tasks, where the agent might iterate for hundreds of
   tool calls.

### Anyrun Manages scheduling the multiple pods across the cluster

1. Within a cluster,a distributed set of Anyrun managers schedule pods, scale cloud compute provisioned
   across multiple regions, and perform state reconciliation to manage hundreds of thousands of pods per cluster.

## Inference Service

### how the model weights been shared across clusters without stopping the training cluster ?

1. Compression, upload, and hotload signaling are fully pipelined in background workers so that training is never blocked.

### How GPU compute worked for Inference ?

1. During the Composer 2 training run, we ran inference across geographically distributed
   clusters in the US and Europe. Each cluster independently downloads and reconstructs
   weights from the shared delta chain, requiring no direct connectivity to the training cluster, enabling world-scale distributed RL inference over commodity cloud storage.

### what are the metadata expected while inferencing MOE model ?

1. when Environment generate the solution and call the inference service
   the model should expected to return this metaData with for each generation

```json
{
  "policy_version": 104,
  "tokens": [...],
  "old_logprobs": [...],
  "moe_expert_indices": [...]
}
```

## Things which is hard to observer/understand | need clarification

1. To minimize the number of training job restarts, we use a reactive configuration system and support live code updates on a per-process level; when new code is deployed, existing actors are drained of in-flight requests and transparently replaced.

2.We run passive and active health checks on all
nodes during training; upon detection of a hardware fault, we mark the node as unhealthy
for scheduling but continue training with warm standby nodes
