Puppet::Type.newtype(:elb_loadbalancer_member) do
  @doc = 'Type representing an ELB load balancer member.'

  ensurable

  # elb-name-01:ec2-instance-01
  newparam(:name, namevar: true) do
    desc 'The namevar is a mix of ELB load balancer name and the instance name.'
    validate do |value|
      fail 'name should not be empty' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
      fail 'name should has : separating load balancer name and instance name' unless value.include?(':')
    end
  end

  newproperty(:region) do
    desc 'The region in which to manage the load balancer member.'
    validate do |value|
      fail 'region must not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

end
