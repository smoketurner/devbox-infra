"""Delete stale workspace snapshots, keeping the newest N plus the published one.

Runs as an aws:executeScript step under the automation role. Selects this
pipeline's snapshots by tag, sorts newest-first, and deletes everything past the
retention count -- but never the snapshot id currently published in the SSM
parameter, and never a snapshot tagged devbox:keep=true.
"""

import boto3


def handler(events, _context):
    retention = int(events["RetentionCount"])
    param_name = events["SnapshotParameter"]

    ec2 = boto3.client("ec2")
    ssm = boto3.client("ssm")

    try:
        current = ssm.get_parameter(Name=param_name)["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        current = None

    snapshots = ec2.describe_snapshots(
        OwnerIds=["self"],
        Filters=[{"Name": "tag:devbox:role", "Values": ["workspace-snapshot"]}],
    )["Snapshots"]

    def kept(snapshot):
        return any(
            tag["Key"] == "devbox:keep" and tag["Value"] == "true"
            for tag in snapshot.get("Tags", [])
        )

    candidates = [s for s in snapshots if not kept(s)]
    candidates.sort(key=lambda s: s["StartTime"], reverse=True)

    survivors = {s["SnapshotId"] for s in candidates[:retention]}
    if current:
        survivors.add(current)

    deleted = []
    for snapshot in candidates:
        snapshot_id = snapshot["SnapshotId"]
        if snapshot_id in survivors:
            continue
        ec2.delete_snapshot(SnapshotId=snapshot_id)
        deleted.append(snapshot_id)

    return {"deleted": deleted, "retained": sorted(survivors)}
