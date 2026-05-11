```mermaid

flowchart TB
    subgraph INFERENCE_SERVICE["Inference Service"]
        ROUTER["Request Router"]
        BATCHER["Dynamic Batcher"]
        REPLICA1["Model Replica 1<br/>active_policy=v105"]
        REPLICA2["Model Replica 2<br/>active_policy=v104<br/>loading=v105"]
        REPLICA3["Model Replica 3<br/>active_policy=v105"]
        HOTLOAD["Hotload Controller"]
        DELTA_DL["Delta Downloader"]
        WEIGHT_CACHE["Local Weight Cache"]
        ROUTE_REPLAY["MoE Route Metadata Exporter"]
    end

    ROUTER --> BATCHER
    BATCHER --> REPLICA1
    BATCHER --> REPLICA2
    BATCHER --> REPLICA3

    DELTA_DL --> WEIGHT_CACHE
    WEIGHT_CACHE --> HOTLOAD
    HOTLOAD --> REPLICA1
    HOTLOAD --> REPLICA2
    HOTLOAD --> REPLICA3

    REPLICA1 --> ROUTE_REPLAY
    REPLICA2 --> ROUTE_REPLAY
    REPLICA3 --> ROUTE_REPLAY

```



## Hotload workflow


```mermaid

sequenceDiagram
    participant Trainer as GPU Trainer
    participant S3 as Shared S3 Delta Store
    participant Loader as Inference Hotload Thread
    participant Replica as Inference Replica
    participant Router as Request Router

    Trainer->>S3: upload delta v104→v105 + manifest
    Loader->>S3: poll manifest
    Loader->>S3: download shard delta
    Loader->>Loader: reconstruct local tensors
    Loader->>Replica: mark v105 ready
    Router->>Replica: finish active batch using v104
    Replica->>Replica: safe boundary reached
    Replica->>Replica: swap active weight pointer to v105
    Router->>Replica: new requests use v105

```