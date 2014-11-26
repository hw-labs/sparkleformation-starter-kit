SparkleFormation.new(:coolapp_vpc).load(:base, :vpc).overrides do

  parameters(:public_subnet_availability_zone) do
    type 'String'
    default 'us-west-2a'
  end

  dynamic!(:subnet, 'public',
      :vpc_id => ref!(:vpc),
      :route_table => ref!(:public_route_table),
      :availability_zone => ref!(:public_subnet_availability_zone)
  )

end
