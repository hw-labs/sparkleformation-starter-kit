SparkleFormation.new(:vpc_instance_layered).load(:compute_base).overrides do

  description 'make an instance, based on region, ami, subnet, and security group'

  # resource IDs we need from the VPC layer
  %w( vpc_id public_subnet ).each do |r|
    parameters(r.to_sym) do
      type 'String'
    end
  end

  resources(:instance_security_group) do
    type 'AWS::EC2::SecurityGroup'
    properties do
      vpc_id ref!(:vpc_id)
      group_description 'allow access to ec2 instance'
      security_group_ingress _array(
        -> {
          ip_protocol 'tcp'
          from_port 22
          to_port 22
          cidr_ip '0.0.0.0/0'
        }
      )
    end
  end

  resources(:ec2_instance) do
    type 'AWS::EC2::Instance'
    properties do
      instance_type ref!(:instance_type)
      image_id ref!(:ami_id)
      security_group_ids [ref!(:instance_security_group)]
      subnet_id ref!(:public_subnet)
      key_name ref!(:key_name)
      user_data base64!(
        join!(
          "#!/bin/bash -v\n",
          "curl -L https://www.opscode.com/chef/install.sh -o /tmp/install-chef.sh\n",
          "bash /tmp/install-chef.sh\n",
          # since we don't have a wait condition nor a handle for it,
          # this currently does nothing
          "# If all went well, signal success\n",
          "cfn-signal -e $? -r 'Chef Server configuration'\n"
        )
      )
    end
  end

  resources(:instance_elastic_ip) do
    type 'AWS::EC2::EIP'
    properties do
      domain 'vpc'
      instance_id ref!(:ec2_instance)
    end
  end

  outputs do
    instance_id do
      description 'Instance Id of newly created instance'
      value ref!(:ec2_instance)
    end

    instance_ip do
      description 'Public IP address of newly created instance'
      value ref!(:instance_elastic_ip)
    end
  end
end
