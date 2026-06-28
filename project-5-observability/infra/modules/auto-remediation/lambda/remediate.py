"""
GuardDuty auto-remediation Lambda.

Triggered by EventBridge when a GuardDuty finding has severity >= 7 (HIGH/CRITICAL).
For EC2-targeting findings, the affected instance is moved to an isolation security
group that blocks all inbound/outbound traffic, preventing lateral movement while
the security team investigates.

The remediation is conservative by design:
  - Only HIGH/CRITICAL severity triggers action (< 7.0 is logged and skipped)
  - Only EC2 instance findings trigger isolation (IAM findings get a notification only)
  - All actions are tagged and logged for the post-incident audit trail
  - The original security groups are recorded in instance tags so they can be restored
"""

import json
import logging
import os
import boto3
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN   = os.environ["SNS_TOPIC_ARN"]
ISOLATION_SG_ID = os.environ["ISOLATION_SG_ID"]


def handler(event: dict, context) -> dict:
    detail   = event.get("detail", {})
    severity = detail.get("severity", 0)
    finding_type = detail.get("type", "Unknown")
    finding_id   = detail.get("id", "Unknown")
    region       = event.get("region", "unknown")

    logger.info(json.dumps({
        "event":        "guardduty_finding_received",
        "finding_id":   finding_id,
        "finding_type": finding_type,
        "severity":     severity,
        "region":       region,
    }))

    if severity < 7.0:
        logger.info(f"Severity {severity} is below remediation threshold (7.0) — no action")
        return {"status": "skipped", "reason": "below_threshold", "severity": severity}

    resource = detail.get("resource", {})

    if "instanceDetails" in resource:
        instance_id = resource["instanceDetails"]["instanceId"]
        result = isolate_instance(instance_id, finding_type, finding_id, severity)
        notify(instance_id, finding_type, severity, result, region)
        return result

    # For non-EC2 findings: notify but do not auto-remediate
    # (IAM, S3, Kubernetes findings require human review before action)
    notify_no_action(finding_type, severity, resource, region)
    return {"status": "notified", "reason": "no_ec2_resource"}


def isolate_instance(instance_id: str, finding_type: str, finding_id: str, severity: float) -> dict:
    """
    Move an EC2 instance to an isolation security group.

    The isolation SG has no inbound or outbound rules — the instance can no longer
    communicate with anything. Original SGs are saved in an instance tag so they
    can be restored after investigation without guessing.
    """
    now = datetime.now(timezone.utc).isoformat()

    try:
        resp = ec2.describe_instances(InstanceIds=[instance_id])
        current_sgs = [
            sg["GroupId"]
            for reservation in resp["Reservations"]
            for inst in reservation["Instances"]
            for sg in inst["SecurityGroups"]
        ]
    except Exception as e:
        logger.error(f"Failed to describe instance {instance_id}: {e}")
        return {"status": "error", "error": str(e), "instance_id": instance_id}

    # Tag before modifying so the audit trail captures intent
    ec2.create_tags(
        Resources=[instance_id],
        Tags=[
            {"Key": "SecurityStatus",      "Value": "ISOLATED"},
            {"Key": "IsolatedAt",          "Value": now},
            {"Key": "GuardDutyFindingId",  "Value": finding_id},
            {"Key": "GuardDutyFindingType","Value": finding_type},
            {"Key": "OriginalSGs",         "Value": json.dumps(current_sgs)},
        ],
    )

    try:
        ec2.modify_instance_attribute(
            InstanceId=instance_id,
            Groups=[ISOLATION_SG_ID],
        )
    except Exception as e:
        logger.error(f"Failed to isolate instance {instance_id}: {e}")
        return {"status": "error", "error": str(e), "instance_id": instance_id}

    logger.info(json.dumps({
        "event":          "instance_isolated",
        "instance_id":    instance_id,
        "removed_sgs":    current_sgs,
        "isolation_sg":   ISOLATION_SG_ID,
        "finding_type":   finding_type,
        "severity":       severity,
        "isolated_at":    now,
    }))

    return {
        "status":       "isolated",
        "instance_id":  instance_id,
        "original_sgs": current_sgs,
        "isolated_at":  now,
    }


def notify(instance_id: str, finding_type: str, severity: float, result: dict, region: str):
    status = result.get("status", "unknown")
    subject = f"[{severity:.1f}] GuardDuty: {finding_type} — instance {status}"

    message = (
        f"GuardDuty AUTO-REMEDIATION\n\n"
        f"Finding:    {finding_type}\n"
        f"Severity:   {severity}\n"
        f"Instance:   {instance_id}\n"
        f"Region:     {region}\n"
        f"Action:     {status.upper()}\n"
    )

    if status == "isolated":
        message += (
            f"Original SGs: {result.get('original_sgs', [])}\n"
            f"Isolated at:  {result.get('isolated_at', '')}\n\n"
            f"Next steps:\n"
            f"  1. Review CloudTrail for activity from this instance\n"
            f"  2. Capture forensic evidence (memory dump, VPC Flow Logs)\n"
            f"  3. Restore SGs or terminate: aws ec2 modify-instance-attribute "
            f"--instance-id {instance_id} --groups <original-sg-ids>\n"
        )

    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)
    logger.info(f"SNS notification sent: {subject}")


def notify_no_action(finding_type: str, severity: float, resource: dict, region: str):
    subject = f"[{severity:.1f}] GuardDuty finding: {finding_type} — manual review required"
    message = (
        f"GuardDuty Finding — NO AUTOMATIC REMEDIATION\n\n"
        f"Finding:  {finding_type}\n"
        f"Severity: {severity}\n"
        f"Region:   {region}\n"
        f"Resource: {json.dumps(resource, indent=2)}\n\n"
        f"This finding type requires manual investigation. Review in:\n"
        f"  https://{region}.console.aws.amazon.com/guardduty/home\n"
    )
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)
