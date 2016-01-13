Puppet::Type.newtype(:route53_private_zone) do
  @doc = 'Type representing an Route53 DNS zone.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of DNS zone group.'
    validate do |value|
      fail Puppet::Error, 'Empty values are not allowed' if value == ''
    end
  end

  newparam(:vpc_region) do
    validate do |value|
      fail Puppet::Error, 'Empty values are not allowed' if value == ''
    end
  end

  newparam(:vpc) do
    validate do |value|
      fail Puppet::Error, 'Empty values are not allowed' if value == ''
    end
  end
end
