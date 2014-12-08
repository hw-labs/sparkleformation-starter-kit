# SparkleFormation: Build infrastructure with CloudFormation without losing your sanity.

## Introduction
This article assumes some familiarity with CloudFormation concepts such as stack parameters, resources,
mappings and outputs. See the [AWS Advent CloudFormation Primer](http://awsadvent.tumblr.com/post/37391299521/cloudformation-primer) for an introduction.

Although CloudFormation templates are billed as reusable, many users will attest that as these
monolithic JSON documents grow larger, they become ["all encompassing JSON file[s] of darkness,"](http://www.unixdaemon.net/cloud/the-four-stages-of-cloudformation.html)
and actually reusing code between templates becomes a frustrating copypasta exercise.

From another perspective these JSON documents are actually just hashes, and with a minimal DSL we
can build these hashes programmatically. [SparkleFormation](https://github.com/sparkleformation/sparkle_formation/) provides a Ruby DSL for merging
and compiling hashes into CFN templates, and helpers which invoke CloudFormation's [intrinsic functions](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference.html)
(e.g. Ref, Attr, Join, Map).

SparkleFormation's DSL implementation is intentionally loose, imposing little of its own
opinion on how your template should be constructed. Provided you are already familiar with
CloudFormation template concepts and some minimal ammount of Ruby, the rest is merging hashes.

## Templates
Just as with CloudFormation, the template is the high-level object. In SparkleFormation we instantiate a new template
like so:

```ruby
SparkleFormation.new(:foo)
```

But an empty template isn't going to help us much, so let's step into it and at least insert the required
`AWSTemplateFormatVersion` specification:

```ruby
SparkleFormation.new(:foo) do
  _set('AWSTemplateFormatVersion', '2010-09-09')
end
```

In the above case we use the `_set` helper method because we are setting a top-level key with a string value.
When we are working with hashes we can use a block syntax, as shown here adding a parameter to the top-level
`Parameters` hash that CloudFormation expects:

```
SparkleFormation.new(:foo) do
  _set('AWSTemplateFormatVersion', '2010-09-09')

  parameters(:food) do
    type 'String'
    description 'what do you want to eat?'
    allowed_values %w( tacos nachos hotdogs )
  end
end
```


## Reusability

SparkleFormation provides primatives to help you build templates out of reusable code, namely:

* Components
* Dynamics
* Registries

### Components
Here's a component we'll name `environment` which defines our allowed environment parameter values:

```ruby
SparkleFormation.build do
  _set('AWSTemplateFormatVersion', '2010-09-09')
  parameters(:environment) do
    type 'String'
    default 'test'
    allowed_values %w( test staging production )
  end
end
```

Resources, parameters and other CloudFormation configuration written into a SparkleFormation component are statically
inserted into any templates using the `load` method. Now all our stack templates can reuse the same component so
updating the list of environments across our entire infrastructure becomes a snap. Once a template has loaded a
component, it can then step into the configuration provided by the component to make modifications.

In this template example we load the `environment` component (above) and override the allowed values for the environment
parameter the component provides:

```ruby
SparkleFormation.new(:perpetual_beta).load(:environment).overrides do
  parameters(:environment) do
    allowed_values %w( test staging )
  end
end
```

### Dynamics
Where as components are loaded once at the instantiation of a SparkleFormation template, dynamics are inserted one or
more times throughout a template. They iteratively generate unique resources based on the name and optional
configuration they are passed when inserted.

In this example we insert a `launch_config` dynamic and pass it a config object containing a run list:

```
SparkleFormation.new('zookeeper').load(:base).overrides do
  dynamic!(:launch_config, 'zookeeper', :run_list => ['role[zookeeperd]'])

  ...

end
```

The `launch_config` dynamic (not pictured) can then use intrisic functions like `Fn::Join` to insert data passed in the config deep inside a launch
configuration, as in this case where we want our template to tell Chef what our run list should be.

### Registries
Similar to dynamics, a registry entry can be inserted at any point in a SparkleFormation template or dynamic. e.g. a
registry entry can be used to share the same metadata between both AWS::AutoScaling::LaunchConfiguration and
AWS::EC2::Instance resources.

## Translating a ghost of AWS Advent past
This JSON template from a previous AWS Advent article provisions a single EC2 instance into an
existing VPC subnet and security group:

```javascript
{
    "AWSTemplateFormatVersion" : "2010-09-09",

    "Description" : "make an instance, based on region, ami, subnet, and security group",

    "Parameters" : {

        "KeyName" : {
            "Description" : "Name of an existing EC2 KeyPair to enable SSH access to the instance",
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
            "Description" : "AMI to use"

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
SparkleFormation.new(:vpc_instance).new do
  set!('AWSTemplateFormatVersion' '2010-09-09')
  description 'make an instance, based on region, ami, subnet, and security group'

  parameters do
    key_name do
      type 'String'
      description 'Name of an existing EC2 KeyPair to enable SSH access to the instance'
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
      description 'AMI to use'
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
SparkleFormation.new(:vpc_instance).load(:base).overrides do

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
describes them.

## Advanced tips and tricks

Since SparkleFormation is Ruby, we can get a little fancy. Let's say we want to build 3 subnets into an existing VPC. If we know the VPC's /16 subnet we can provide it as an environment variable (`export VPC_SUBNET="10.1.0.0/16"`), and then call that variable in a template that generates additional subnets:
```ruby
SparkleFormation.build do
  set!('AWSTemplateFormatVersion', '2010-09-09')

  octets = ENV['VPC_SUBNET].split('.').slice(0,2).join('.')

  subnets = %w(1 2 3)

  parameters(:vpc_id) do
    type 'String'
    description 'Existing VPC ID'
  end

  parameters(:route_table_id) do
    type 'String'
    description 'Existing VPC Route Table'
  end

  subnets.each do |subnet|
    resources("vpc_subnet_#{subnet}".to_sym) do
    type 'AWS::EC2::Subnet'
    properties do
      vpc_id ref!(:vpc_id)
      cidr_block octets + '.' + subnet + '.0/24'
      availability_zone 'us-west-2a'
    end
  end

  resources("vpc_subnet_route_table_association_#{subnet}".to_sym) do
    type 'AWS::EC2::SubnetRouteTableAssociation'
    properties do
      route_table_id ref!(:route_table_id)
      subnet_id ref!("vpc_subnet_#{subnet}".to_sym)
    end
  end
end
```

Of course we could place the subnet and route table association resources into a dynamic, so that we could just call the dynamic with some config:

```ruby
subnets.each do |subnet|
  dynamic!(:vpc_subnet, subnet, subnet_cidr => octets + '.' + subnet + '.0/24')
end
```

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
SparkleFormation.new(:coolapp_asg) do

  parameters(:elb_name) do
    type 'String'
  end

 parameters(:elb_security_group) do
    type 'String'
  end

  ...

end
```

Once our `coolapp_asg` template uses parameter names that match the output names from the `coolapp-elb` stack, we can deploy the app server layer "on top" of the ELB layer using `--apply-stack`:

```bash
$ knife cloudformation create coolapp-asg --apply-stack coolapp-elb

```

Similarly, if we use a SparkleFormation template to build our VPC, we can set a number of VPC outputs that will be useful when building stacks inside the VPC:

```ruby
  outputs do
    vpc_id do
      description 'VPC ID'
      value ref!(:vpc_id)
    end
    subnet_id do
      description 'VPC Subnet ID'
      value ref!(:subnet_id)
    end
    route_table_id do
      description 'VPC Route Table'
      value ref!(:route_table)
    end
  end
```

This 'apply stack' approach is just the latest way in which the SparkleFormation tool chain can help you keep your sanity when building infrastructure with CloudFormation.

## Further reading

I hope this brief tour of SparkleFormation's capabilities has piqued your interest. For some AWS users, the combination of
SparkleFormation and knife-cloudformation helps to address a real pain point in the infrastructure-as-code tool chain,
easing the development and operation of layered infrastructure.

Here's some additional material to help you get started:

* [SparkleFormation documentation](https://github.com/sparkleformation/sparkle_formation/tree/master/docs) - more detailed discussion of the concepts introduced here, and mmore!
* [SparkleFormation starter kit](https://github.com/hw-labs/sparkleformation-starter-kit) - an example repository containing some basic templates for deploying a VPC and an EC2 instance inside that VPC.
* [Sean Porter's SparkleFormation ignite talk from DevOpsDays Vancouver 2014](https://www.youtube.com/watch?v=JnNWn3BoAcM&t=2h40m50s)
