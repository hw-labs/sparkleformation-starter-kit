# SparkleFormation Starter Kit

This repo is provided as a starting point for experimentation and development of CloudFormation templates using [SparkleFormation](https://github.com/sparkleformation/sparkle_formation/) and [knife-cloudformation](https://github.com/hw-labs/knife-cloudformation). For an introduction see our article from the 2014 AWS Advent series, [Build infrastructure with CloudFormation without losing your sanity](AWS_ADVENT.md).

## TL;DR

The `.chef/knife.rb` file in this repository assumes that the environment variables `AWS_DEFAULT_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set with values appropriate for your AWS account.

Run the following to generate a minimal VPC and deploy a single EC2 instance into it:

```
$ bundle install
$ bundle exec knife cloudformation create test-vpc --file cloudformation/vpc.rb --defaults
$ bundle exec knife cloudformation create test-vpc-instance --file cloudformation/vpc_instance.rb --defaults --apply-stack test-vpc
```
