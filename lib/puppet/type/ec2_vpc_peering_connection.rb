require_relative '../../puppet_x/puppetlabs/property/tag.rb'

Puppet::Type.newtype(:ec2_vpc_peering_connection do
  @doc = 'Type representing a VPC Peering Connection.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of the route table.'
    validate do |value|
      fail 'route tables must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newparam(:local_vpc) do
    desc 'VPC to assign the route table to.'
    validate do |value|
      fail 'vpc should be a String' unless value.is_a?(String)
    end
  end

  newparam(:peer_vpc) do
    desc 'Peer VPC to assign to the peering connection'
    validate do |value|
      fail 'vpc should be a String' unless value.is_a?(String)
    end
  end

  newparam(:region) do
    desc 'Region in which to launch the peering connection.'
    validate do |value|
      fail 'region should not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

  newparam(:auto_accept) do
    desc 'Whether to automatically accpet a VPC peering connection.'
    defaultto :false
    newvalues(:true, :'false')
  end

  newproperty(:tags, :parent => PuppetX::Property::AwsTag) do
    desc 'Tags to assign to the peering connection.'
  end

  autorequire(:ec2_vpc) do
    self[:local_vpc]
    self[:peer_vpc]
  end

end
