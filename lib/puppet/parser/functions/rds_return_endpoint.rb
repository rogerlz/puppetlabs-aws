require_relative '../../../puppet_x/puppetlabs/aws.rb'
require 'aws-sdk-core'

module Puppet::Parser::Functions
  newfunction(:rds_return_endpoint, :type => :rvalue) do |args|
    func_name = __method__.to_s.sub!('real_function_','')
    method = :private_ip_address

    unless args.length == 2 then
      raise Puppet::ParseError, ("#{func_name}(): wrong number of arguments (#{args.length}; must be 2)")
    end

    region = args[0]
    rds_instance_name = args[1]

    unless region.instance_of?(String) then
      raise Puppet::ParseError, ("#{func_name}(): Parameter [region] is not a string.  It looks to be a #{filter.class}")
    end

    unless rds_instance_name.instance_of?(String) then
      raise Puppet::ParseError, ("#{func_name}(): Parameter [subnet_id] must be a string")
    end

    response = PuppetX::Puppetlabs::Aws.rds_client(region).describe_db_instances(db_instance_identifier: rds_instance_name)
    response.db_instances[0].endpoint.address   
  end
end
