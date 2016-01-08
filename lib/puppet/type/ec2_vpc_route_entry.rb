require_relative '../../puppet_x/puppetlabs/property/tag.rb'

Puppet::Type.newtype(:ec2_vpc_route_entry) do
  @doc = 'Type representing a VPC route entry.'

  ensurable

  newparam(:destination_cidr_block, namevar: true) do
    desc 'The destination cidr of the route entry.'
    validate do |value|
      fail 'route tables must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newparam(:vpc) do
    desc 'VPC to assign the route entry to.'
    validate do |value|
      fail 'vpc should be a String' unless value.is_a?(String)
    end
  end

  newparam(:route_table) do
    desc 'Route Table to assign the route entry to.'
    validade do |value|
      fail 'route table should be a String' unless value.is_a?(String)
    end
  end

  newparam(:region) do
    desc 'Region in which to launch the route entry.'
    validate do |value|
      fail 'region should not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

  newparam(:gateway) do
    desc 'Gateway to assign the route entry to.'
    validate do |value|
      fail 'gateway should be a String' unless value.is_a?(String)
    end
  end

  autorequire(:ec2_vpc_routetable) do
    self[:route_table]
  end

  autorequire(:ec2_vpc) do
    self[:vpc]
  end

end
