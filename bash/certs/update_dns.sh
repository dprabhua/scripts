#!/bin/bash

HOSTNAME=$1
ip_address=$2

export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export AWS_ROUTE53_ZONEID=

aws route53 wait resource-record-sets-changed --id "$(
    aws route53 change-resource-record-sets \
    --hosted-zone-id "${AWS_ROUTE53_ZONEID}" \
    --query ChangeInfo.Id --output text \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"${HOSTNAME}.\",
          \"ResourceRecords\": [{\"Value\": \"${ip_address}\"}],
          \"Type\": \"A\",
          \"TTL\": 30
        }
      }]
    }"
  )"
