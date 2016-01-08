require_relative '../../puppet_x/puppetlabs/property/tag.rb'

Puppet::Type.newtype(:ec2_vpc_routetable) do
  @doc = 'Type representing a VPC route table.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of the route table.'
    validate do |value|
      fail 'route tables must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:vpc) do
    desc 'VPC to assign the route table to.'
    validate do |value|
      fail 'vpc should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:region) do
    desc 'Region in which to launch the route table.'
    validate do |value|
      fail 'region should not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

  # FIXME (should be property)
  newparam(:routes, :array_matching => :all) do
    desc 'Individual routes for the routing table.'
    # FIXME
    #validate do |value|
    #  ['destination_cidr_block', 'gateway'].each do |key|
    #    fail "routes must include a #{key}" unless value.keys.include?(key)
    #  end
    #end
    def insync?(is)
      is.to_set == should.to_set
    end
  end

  newproperty(:tags, :parent => PuppetX::Property::AwsTag) do
    desc 'Tags to assign to the route table.'
  end

  validate do
    routes = self[:routes]
    if routes
      uniq_gateways = Array(routes).collect { |route| route['gateway'] }.uniq
      uniq_blocks = Array(routes).collect { |route| route['destination_cidr_block'] }.uniq
      fail 'Only one route per gateway allowed' unless uniq_gateways.size == Array(routes).size
      fail 'destination_cidr_block must be unique' unless uniq_blocks.size == Array(routes).size
    end
  end

end
