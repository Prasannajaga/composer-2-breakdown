CREATE TABLE training_runs (
    id BIGSERIAL PRIMARY KEY,
    run_name TEXT NOT NULL,
    status TEXT NOT NULL,
    current_policy_version BIGINT,
    target_group_size INT NOT NULL,
    max_policy_lag INT NOT NULL,
    max_inflight_rollouts INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tasks (
    id BIGSERIAL PRIMARY KEY,
    task_key TEXT NOT NULL UNIQUE,
    task_type TEXT NOT NULL,
    repo_snapshot_id TEXT,
    prompt TEXT NOT NULL,
    setup_command TEXT,
    test_command TEXT,
    hidden_test_command TEXT,
    scoring_config JSONB,
    sampling_weight FLOAT NOT NULL DEFAULT 1.0,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE policy_versions (
    id BIGSERIAL PRIMARY KEY,
    training_run_id BIGINT NOT NULL REFERENCES training_runs(id) ON DELETE CASCADE,
    checkpoint_uri TEXT NOT NULL,
    delta_manifest_uri TEXT,
    parent_policy_version BIGINT REFERENCES policy_versions(id),
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE training_runs
ADD CONSTRAINT fk_training_runs_current_policy_version
FOREIGN KEY (current_policy_version)
REFERENCES policy_versions(id);

CREATE TABLE rollout_groups (
    id BIGSERIAL PRIMARY KEY,
    training_run_id BIGINT NOT NULL REFERENCES training_runs(id) ON DELETE CASCADE,
    task_id BIGINT NOT NULL REFERENCES tasks(id),
    launch_policy_version BIGINT NOT NULL REFERENCES policy_versions(id),
    expected_rollouts INT NOT NULL,
    completed_rollouts INT NOT NULL DEFAULT 0,
    failed_rollouts INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    nfs_checkpoint_uri TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rollouts (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES rollout_groups(id) ON DELETE CASCADE,
    task_id BIGINT NOT NULL REFERENCES tasks(id),
    rollout_key TEXT NOT NULL UNIQUE,
    start_policy_version BIGINT NOT NULL REFERENCES policy_versions(id),
    latest_policy_version BIGINT REFERENCES policy_versions(id),
    status TEXT NOT NULL,
    attempt INT NOT NULL DEFAULT 0,
    reward FLOAT,
    advantage FLOAT,
    token_count INT NOT NULL DEFAULT 0,
    turn_count INT NOT NULL DEFAULT 0,
    tool_call_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE environment_clusters (
    id BIGSERIAL PRIMARY KEY,
    cluster_name TEXT NOT NULL UNIQUE,
    region TEXT NOT NULL,
    k8s_api_endpoint TEXT NOT NULL,
    status TEXT NOT NULL,
    pending_pods INT NOT NULL DEFAULT 0,
    running_pods INT NOT NULL DEFAULT 0,
    failed_pods INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE env_requests (
    id BIGSERIAL PRIMARY KEY,
    rollout_id BIGINT NOT NULL REFERENCES rollouts(id) ON DELETE CASCADE,
    task_id BIGINT NOT NULL REFERENCES tasks(id),
    environment_cluster_id BIGINT NOT NULL REFERENCES environment_clusters(id),
    k8s_namespace TEXT NOT NULL,
    k8s_resource_kind TEXT NOT NULL,
    k8s_resource_name TEXT NOT NULL,
    repo_snapshot_id TEXT,
    cpu_request TEXT,
    memory_request TEXT,
    ephemeral_storage_request TEXT,
    status TEXT NOT NULL,
    failure_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE k8s_environment_events (
    id BIGSERIAL PRIMARY KEY,
    env_request_id BIGINT NOT NULL REFERENCES env_requests(id) ON DELETE CASCADE,
    rollout_id BIGINT NOT NULL REFERENCES rollouts(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    old_status TEXT,
    new_status TEXT,
    k8s_pod_name TEXT,
    k8s_node_name TEXT,
    reason TEXT,
    message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rollout_artifacts (
    id BIGSERIAL PRIMARY KEY,
    rollout_id BIGINT NOT NULL REFERENCES rollouts(id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL,
    uri TEXT NOT NULL,
    byte_size BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tool_calls (
    id BIGSERIAL PRIMARY KEY,
    rollout_id BIGINT NOT NULL REFERENCES rollouts(id) ON DELETE CASCADE,
    turn_index INT NOT NULL,
    tool_name TEXT NOT NULL,
    arguments JSONB,
    status TEXT NOT NULL,
    output_uri TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE verifier_jobs (
    id BIGSERIAL PRIMARY KEY,
    rollout_id BIGINT NOT NULL REFERENCES rollouts(id) ON DELETE CASCADE,
    task_id BIGINT NOT NULL REFERENCES tasks(id),
    k8s_namespace TEXT NOT NULL,
    k8s_job_name TEXT NOT NULL,
    status TEXT NOT NULL,
    reward FLOAT,
    reward_breakdown JSONB,
    result_json JSONB,
    logs_uri TEXT,
    attempt INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE train_ready_objects (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES rollout_groups(id) ON DELETE CASCADE,
    ray_object_ref TEXT,
    nfs_backup_uri TEXT,
    status TEXT NOT NULL,
    byte_size BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE retry_events (
    id BIGSERIAL PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    retry_number INT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE scheduler_events (
    id BIGSERIAL PRIMARY KEY,
    training_run_id BIGINT NOT NULL REFERENCES training_runs(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    old_status TEXT,
    new_status TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);