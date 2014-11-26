# SparkleFormation: Build infrastructure with CloudFormation without losing your sanity.

## Introduction
This article assumes some familiarity with CloudFormation concepts such as stack parameters, resources,
mappings and outputs. See the [AWS Advent CloudFormation Primer](http://awsadvent.tumblr.com/post/37391299521/cloudformation-primer) for an introduction.

Although CloudFormation templates are billed as reusable, many users will attest that as these
monolithic JSON documents grow larger, they become ["all encompassing JSON file[s] of darkness,"](http://www.unixdaemon.net/cloud/the-four-stages-of-cloudformation.html)
and actually reusing code between templates becomes a frustrating copypasta exercise.

## My God, it's full of hashes.

From another perspective these JSON documents are actually just hashes, and with a minimal DSL we
can build these hashes programmatically. [SparkleFormation](https://github.com/sparkleformation/sparkle_formation/) provides a Ruby DSL for merging
and compiling hashes into CFN templates, and helpers which invoke CloudFormation's [intrinsic functions]()
(e.g. Ref, Attr, Join, Map).

SparkleFormation's DSL implementation is intentionally loose, imposing little of its own
opinion on how your template should be constructed. Provided you are already familiar with
CloudFormation template concepts and some minimal ammount of Ruby, the rest is merging hashes.

## A literal translation

This JSON template from a previous AWS Advent article provisions a single EC2 instance into an
existing VPC subnet and security group:

```javascript
{
    "AWSTemplateFormatVersion" : "2010-09-09",

    "Description" : "make an instance, based on region, ami, subnet, and security group",

    "Parameters" : {

        "KeyName" : {
            "Description" : "Name of and existing EC2 KeyPair to enable SSH access to the instance",
            "Type" : "String"
        },

        "VpcId" : {
            "Type" : "String",
            "Description" : "VpcId of your existing Virtual Private Cloud (VPC)"
        },

        "SubnetId" : {
            "Type" : "String",
            "Description" : "SubnetId of an existing subnet in your Virtual Private Cloud (VPC)"
        },

        "AmiId" : {
            "Type" : "String",
            "Description" : "AMI You want to use"

        },

        "SecurityGroupId": {
            "Type" : "String",
            "Description" : "SecurityGroup to use"
        }

    },

    "Resources" : {

        "Ec2Instance" : {
            "Type" : "AWS::EC2::Instance",
            "Properties" : {
                "ImageId" : { "Ref" : "AmiId" },
                "SecurityGroupIds" : [{ "Ref" : "SecurityGroupId" }],
                "SubnetId" : { "Ref" : "SubnetId" },
                "KeyName" : { "Ref" : "KeyName" },
                "UserData" : { "Fn::Base64" : { "Fn::Join" :
                                                ["", [
                                                    "#!/bin/bash -v\n",
                                                    "curl http://aprivatebucket.s3.amazonaws.com/bootstrap.sh -o /tmp/bootstrap.sh\n",
                                                    "bash /tmp/bootstrap.sh\n",
                                                    "# If all went well, signal success\n",
                                                    "cfn-signal -e $? -r 'Chef Server configuration'\n"
                                                ]]}}
            }
        }
    },

    "Outputs" : {
        "InstanceId" : {
            "Value" : { "Ref" : "Ec2Instance" },
            "Description" : "Instance Id of newly created instance"
        },

        "Subnet" : {
            "Value" : { "Ref" : "SubnetId" },
            "Description" : "Subnet of instance"
        },

        "SecurityGroupId" : {
            "Value" : { "Ref" : "SecurityGroupId" },
            "Description" : "Security Group of instance"
        }
    }

}

```

Not terrible, but the JSON is a little hard on the eyes. Here's the same thing in Ruby,
using SparkleFormation:


```ruby
SparkleFormation.new('vpc-instance').new do
  set!('AWSTemplateFormatVersion' '2010-09-09')
  description 'make an instance, based on region, ami, subnet, and security group'

  parameters do
    key_name do
      type 'String'
      description 'Name of and existing EC2 KeyPair to enable SSH access to the instance'
    end
    vpc_id do
      type 'String'
      description 'VpcId of your existing Virtual Private Cloud (VPC)'
    end
    subnet_id do
      type 'String'
      description 'SubnetId of an existing subnet in your Virtual Private Cloud (VPC)'
    end
    ami_id do
      type 'String'
      description 'AMI You want to use'
    end
    security_group_id do
      type 'String'
      description 'SecurityGroup to use'
    end
  end

  resources(:ec2_instance) do
    type 'AWS::EC2::Instance'
    properties do
      image_id ref!(:ami_id)
      security_group_ids [ref!(:security_group_id)]
      subnet_id ref!(:subnet_id)
      key_name ref!(:key_name)
      user_data base64!(
        join!(
          "#!/bin/bash -v\n",
          "curl http://aprivatebucket.s3.amazonaws.com/bootstrap.sh -o /tmp/bootstrap.sh\n",
          "bash /tmp/bootstrap.sh\n",
          "# If all went well, signal success\n",
          "cfn-signal -e $? -r 'Chef Server configuration'\n"
        )
      )
    end
  end

  outputs do
    instance_id do
      description 'Instance Id of newly created instance'
      value ref!(:instance_id)
    end
    subnet do
      description 'Subnet of instance'
      value ref!(:subnet_id)
    end
    security_group_id do
      description 'Security group of instance'
      value ref!(:security_group_id)
    end
  end

end

```

Without taking advantage of any of SparkleFormation's special capabilities, this translation is
already a few lines shorter and easier to read as well. That's a good start, but we can do better.

## Reusability building blocks

SparkleFormation provides the following concepts to help you build templates out of reusable code:

* Components - static configuration which can be reused between many stack templates

* Dynamics -  injecting a dynamic with name and configuration arguments inserts unique resources
  generated iteratively.

* Registries - similar to dynamics, a registry entry can be inserted at any point in a
  SparkleFormation template or dynamic. e.g. a registry entry can be used to share the same metadata
  between both AWS::AutoScaling::LaunchConfiguration and AWS::EC2::Instance resources.

## A simple example of reusability in action

The template format version specification and parameters required for this template are common to any
stack where EC2 compute resources may be used, whether they be single EC2 instances or
Auto Scaling Groups, so lets take advantage of some SparkleFormation features to make them reusable.

Here we have a `base` component that inserts the common parameters into templates which load it:

```ruby
SparkleFormation.build do
  set!('AWSTemplateFormatVersion', '2010-09-09')

  parameters do
    key_name do
      type 'String'
      description 'Name of and existing EC2 KeyPair to enable SSH access to the instance'
    end
    vpc_id do
      type 'String'
      description 'VpcId of your existing Virtual Private Cloud (VPC)'
    end
    subnet_id do
      type 'String'
      description 'SubnetId of an existing subnet in your Virtual Private Cloud (VPC)'
    end
    ami_id do
      type 'String'
      description 'AMI You want to use'
    end
    security_group_id do
      type 'String'
      description 'SecurityGroup to use'
    end
  end

  outputs do
    subnet do
      description 'Subnet of instance'
      value ref!(:subnet_id)
    end
    security_group_id do
      description 'Security group of instance'
      value ref!(:security_group_id)
    end
  end

end

```

Now that the template version and common parameters have moved into the new `base` component, we can
make use of them by loading that component as we instantiate our new template, specifying that the
template will override any pieces of the component where the two intersect.

Let's update the SparkleFormation template to make use of the new `base` component:

```ruby
SparkleFormation.new('vpc-instance').load(:base).overrides do

  description 'make an instance, based on region, ami, subnet, and security group'

  resources(:ec2_instance) do
    type 'AWS::EC2::Instance'
    properties do
      image_id ref!(:ami_id)
      security_group_ids [ref!(:security_group_id)]
      subnet_id ref!(:subnet_id)
      key_name ref!(:key_name)
      user_data base64!(
        join!(
          "#!/bin/bash -v\n",
          "curl http://aprivatebucket.s3.amazonaws.com/bootstrap.sh -o /tmp/bootstrap.sh\n",
          "bash /tmp/bootstrap.sh\n",
          "# If all went well, signal success\n",
          "cfn-signal -e $? -r 'Chef Server configuration'\n"
        )
      )
    end
  end

  outputs do
    instance_id do
      description 'Instance Id of newly created instance'
      value ref!(:instance_id)
    end
  end
end

```

Because the `base `component includes the parameters we need, the template no longer explicitly
describes them. You may also notice that figures 3 and 4 both specify outputs; these are merged
together when the hash is rendered into JSON.

## Okay, this all sounds great! But how do I *operate* it?

SparkleFormation by itself does not implement any means of sending its output to the CloudFormation
API. In this simple case, a SparkleFormation template named `ec2_example.rb` is output to JSON
which you can use with CloudFormation as usual:

```ruby
require 'sparkle_formation'
require 'json'

puts JSON.pretty_generate(
  SparkleFormation.compile('ec2_example.rb')
)
```

The [knife-cloudformation](https://github.com/hw-labs/knife-cloudformation) plugin for Chef's `knife` command adds sub-commands for creating, updating,
inspecting and destroying CloudFormation stacks described by SparkleFormation code or plain JSON
templates. Using knife-cloudformation does not require Chef to be part of your toolchain, it simply
leverages knife as an execution platform.

Advent readers may recall a previous article on [strategies for reusable CloudFormation templates](http://awsadvent.tumblr.com/post/38685647817/strategies-reusable-cfn-templates)
which advocates a "layer cake" approach to deploying infrastructure using CloudFormation stacks:

> The overall approach is that your templates should have sufficient parameters and outputs to be
> re-usable across environments like dev, stage, qa, or prod and that each layer’s template builds on
> the next.

Of course this is all well and good, until we find ourselves, once again, copying and pasting.
This time its stack outputs instead of JSON, but again, we can do better.

The recent 0.2.0 release of knife-cloudformation adds a new `--apply-stack` parameter
which makes operating "layer cake" infrastructure much easier.

When passed one or more instances of `--apply-stack STACKNAME`, knife-cloudformation will cache the outputs of the named stack
and use the values of those outputs as the default values for parameters of the same name in the stack you are creating.

For example, a stack "coolapp-elb" which provisions an ELB and an associated security group has been configured with the following outputs:

```shell
$ knife cloudformation describe coolapp-elb
Resources for stack: coolapp-elb
Updated                  Logical Id                Type                                     Status
Status Reason
2014-11-17 22:54:28 UTC  CoolappElb               AWS::ElasticLoadBalancing::LoadBalancer
CREATE_COMPLETE
2014-11-17 22:54:47 UTC  CoolappElbSecurityGroup  AWS::EC2::SecurityGroup
CREATE_COMPLETE

Outputs for stack: coolapp-elb
Elb Dns: coolapp-elb-25352800.us-east-1.elb.amazonaws.com
Elb Name: coolapp-elb
Elb Security Group: coolapp-elb-CoolappElbSecurityGroup-JSR4RUT66Z66
```

The values from the ElbName and ElbSecurityGroup would be of use to us in attaching an app server
auto scaling group to this ELB, and we could use those values automatically by setting parameter
names in the app server template which match the ELB stack's output names:

```ruby
SparkleFormation.new('coolapp-asg') do

  parameters(:elb_name) do
    type 'String'
  end

 parameters(:elb_security_group) do
    type 'String'
  end

  ...

end
```

Now that my `coolapp-asg` template uses parameter names that match the output names from the `coolapp-elb` stack, I can deploy the app server layer "on top" of the ELB layer using `--apply-stack`:

```base
$ knife cloudformation create coolapp-asg --apply-stack coolapp-elb

```


