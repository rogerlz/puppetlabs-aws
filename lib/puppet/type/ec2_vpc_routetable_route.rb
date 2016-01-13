Puppet::Type.newtype(:ec2_vpc_routetable_route) do
  @doc = 'Type representing a VPC route entry.'

  ensurable

  def self.title_patterns
    [
      # We could define multiple patterns, but we only need one
      [
        # pattern 01 to parse a title of the form <a>:<b>
        /^(.*):(.*)$/,
        [
          # the regex returns two values. We want them to be
          # stored as param a and b and we pass a proc that
          # does not do any conversion
          [:routetable_name, lambda{|x| x} ],
          [:destination_cidr_block, lambda{|x| x} ]
        ]
      ]
    ]
  end

  newparam(:name) do
  end

  newparam(:destination_cidr_block, namevar: true) do
    desc 'The destination cidr of the route entry.'
    validate do |value|
      fail 'route tables must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newparam(:routetable_name, namevar: true) do
    desc 'Route Table to assign the route entry to.'
    validate do |value|
      fail 'route table should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:region) do
    desc 'Region in which to launch the route entry.'
    validate do |value|
      fail 'region should not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:gateway) do
    desc 'Gateway to assign the route entry to.'
    validate do |value|
      fail 'gateway should be a String' unless value.is_a?(String)
    end
  end

#  autorequire(:ec2_vpc_routetable) do
#    self[:routetable_name]
#  end

end
