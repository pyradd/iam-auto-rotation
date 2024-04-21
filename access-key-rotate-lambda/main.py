# (c) 2021 Amazon Web Services, Inc. or its affiliates. All Rights Reserved.
# This AWS Content
# is provided subject to the terms of the AWS Customer Agreement available at
# https://aws.amazon.com/agreement/ or other written agreement between Customer
# and Amazon Web Services, Inc.


import time
import json

from config import Config, log
from force_rotation_handler import check_force_rotate_users
from account_scan import get_actions_for_account
from notification_handler import send_to_notifier
from key_actions import log_actions, execute_actions
import boto3

timestamp = int(round(time.time() * 1000))

config = Config()


def lambda_handler(event, context):
    """Handler for Lambda.

    :param event: Dictionary object sent to lambda function using payload
    :param context: Lambda context object
    """

    log.info("Function starting.")
    log.info(event)

    # Error handling - Ensure that the correct object is getting passed
    # to the function

    # check for users to be force rotated via test event
    force_rotate_users = check_force_rotate_users(event)

    # check for dryrun flag
    dryrun = str(event.get("dryrun")).lower() == "true" or config.dryrun
    account_session = boto3.session.Session()

    sts_client = account_session.client("sts")
    aws_account_id = sts_client.get_caller_identity()["Account"]
    iam_client = account_session.client("iam")
    account_name = iam_client.list_account_aliases()["AccountAliases"][0]

    account_emails = json.loads(config.recipientEmails)
    log.info(
        f"Currently evaluating Account ID: {aws_account_id} | Account Name: {account_name}"
    )

    log.info("Secret will be stored in tenant  Account")
    central_account_sm_client = None
    action_queue = get_actions_for_account(account_session, force_rotate_users)

    if action_queue:
        log_actions(action_queue, dryrun)

        # Extract subsets of actions for resource owners
        resource_owners = {action.get("resource_owner") for action in action_queue}
        resource_owners.discard(None)
        resource_actions = {}
        for resource_owner in resource_owners:
            resource_actions[resource_owner] = [
                action
                for action in action_queue
                if action.get("resource_owner") == resource_owner
            ]

        # Send notifications
        if dryrun:
            send_to_notifier(
                context,
                aws_account_id,
                account_name,
                account_emails,
                action_queue,
                dryrun,
                config.emailTemplateAudit,
            )
            for resource_owner in resource_owners:
                send_to_notifier(
                    context,
                    aws_account_id,
                    account_name,
                    resource_owner,
                    resource_actions[resource_owner],
                    dryrun,
                    config.emailTemplateAudit,
                )
        else:
            execute_actions(action_queue, account_session, central_account_sm_client)
            send_to_notifier(
                context,
                aws_account_id,
                account_name,
                account_emails,
                action_queue,
                dryrun,
                config.emailTemplateEnforce,
            )
            for resource_owner in resource_owners:
                send_to_notifier(
                    context,
                    aws_account_id,
                    account_name,
                    resource_owner,
                    resource_actions[resource_owner],
                    dryrun,
                    config.emailTemplateEnforce,
                )

    log.info("---------------------------")
    log.info("Function has completed.")
