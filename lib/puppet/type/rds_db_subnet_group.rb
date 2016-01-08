Puppet::Type.newtype(:rds_db_subnet_group) do
  @doc = 'Type representing an RDS Subnet Group.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name for the DB subnet group (also known as the db_subnet_group_name).'
    validate do |value|
      fail 'name should be a String' unless value.is_a?(String)
      fail 'name must not be default' if value == 'default'
    end
  end

  newproperty(:description) do
    desc 'The description for the DB subnet group.'
    validate do |value|
      fail 'description should be a String' unless value.is_a?(String)
      fail 'description should not be blank' if value == ''
    end
  end

  newparam(:subnets, :array_matching => :all) do
    desc 'The EC2 Subnets for the DB subnet group.'
    validate do |value|
      fail 'subnets should not be blank' if value == ''
      fail 'subnets should be a Array' unless value.kind_of?(Array)
      fail 'subnets should has a minimum of 2' if value.length < 2
    end
  end

  newproperty(:region) do
    desc 'The region in which to create the db_securitygroup.'
    validate do |value|
      fail 'region should be a String' unless value.is_a?(String)
      fail 'region should not contain spaces' if value =~ /\s/
    end
  end

end
