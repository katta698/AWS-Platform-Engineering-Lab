Resources:
  RequiredTags:
    Type: "AWS::Config::ConfigRule"
    Properties:
      ConfigRuleName: week12-required-tags
      Description: >-
        Checks that S3 buckets, EC2 instances, and EBS volumes carry the lab's
        mandatory governance tags. Notify-only -- non-compliant resources
        surface in the daily compliance digest, not auto-tagged (a tag value
        can't be safely invented by automation).
      Scope:
        ComplianceResourceTypes:
          - "AWS::S3::Bucket"
          - "AWS::EC2::Instance"
          - "AWS::EC2::Volume"
      Source:
        Owner: AWS
        SourceIdentifier: REQUIRED_TAGS
      InputParameters:
        tag1Key: "${required_tag_1}"
        tag2Key: "${required_tag_2}"
        tag3Key: "${required_tag_3}"

  S3BucketVersioningEnabled:
    Type: "AWS::Config::ConfigRule"
    Properties:
      ConfigRuleName: week12-s3-bucket-versioning-enabled
      Description: >-
        Checks that S3 buckets tagged ${remediation_tag_key}=${remediation_tag_value}
        have versioning enabled. Not covered by Security Hub FSBP, which only
        checks S3 public-access and SSL-in-transit.
      Scope:
        # Tag-only -- AWS Config's Scope object rejects combining
        # ComplianceResourceTypes with TagKey/TagValue ("Scope cannot be
        # applied to both resource and tag", confirmed live on first apply).
        # The underlying managed rule only ever evaluates S3 buckets anyway.
        TagKey: "${remediation_tag_key}"
        TagValue: "${remediation_tag_value}"
      Source:
        Owner: AWS
        SourceIdentifier: S3_BUCKET_VERSIONING_ENABLED

  S3BucketVersioningEnabledRemediation:
    DependsOn: S3BucketVersioningEnabled
    Type: "AWS::Config::RemediationConfiguration"
    Properties:
      ConfigRuleName: week12-s3-bucket-versioning-enabled
      ResourceType: "AWS::S3::Bucket"
      TargetId: "AWS-ConfigureS3BucketVersioning"
      TargetType: "SSM_DOCUMENT"
      TargetVersion: "1"
      Parameters:
        AutomationAssumeRole:
          StaticValue:
            Values:
              - "${automation_role_arn}"
        BucketName:
          ResourceValue:
            Value: "RESOURCE_ID"
        VersioningState:
          StaticValue:
            Values:
              - "Enabled"
      ExecutionControls:
        SsmControls:
          ConcurrentExecutionRatePercentage: 10
          ErrorPercentage: 10
      Automatic: true
      MaximumAutomaticAttempts: 3
      RetryAttemptSeconds: 60

  S3BucketServerSideEncryptionEnabled:
    Type: "AWS::Config::ConfigRule"
    Properties:
      ConfigRuleName: week12-s3-bucket-sse-enabled
      Description: >-
        Checks that S3 buckets tagged ${remediation_tag_key}=${remediation_tag_value}
        have default server-side encryption enabled. Not covered by Security
        Hub FSBP, which only checks S3 public-access and SSL-in-transit, not
        at-rest SSE.
      Scope:
        # Tag-only -- see the note on S3BucketVersioningEnabled's Scope above.
        TagKey: "${remediation_tag_key}"
        TagValue: "${remediation_tag_value}"
      Source:
        Owner: AWS
        SourceIdentifier: S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED

  S3BucketServerSideEncryptionEnabledRemediation:
    DependsOn: S3BucketServerSideEncryptionEnabled
    Type: "AWS::Config::RemediationConfiguration"
    Properties:
      ConfigRuleName: week12-s3-bucket-sse-enabled
      ResourceType: "AWS::S3::Bucket"
      TargetId: "AWS-EnableS3BucketEncryption"
      TargetType: "SSM_DOCUMENT"
      TargetVersion: "1"
      Parameters:
        AutomationAssumeRole:
          StaticValue:
            Values:
              - "${automation_role_arn}"
        BucketName:
          ResourceValue:
            Value: "RESOURCE_ID"
        SSEAlgorithm:
          StaticValue:
            Values:
              - "AES256"
      ExecutionControls:
        SsmControls:
          ConcurrentExecutionRatePercentage: 10
          ErrorPercentage: 10
      Automatic: true
      MaximumAutomaticAttempts: 3
      RetryAttemptSeconds: 60
