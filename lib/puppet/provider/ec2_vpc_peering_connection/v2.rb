require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:ec2_vpc_peering_connection).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods
  remove_method :tags=

  def self.instances
    regions.collect do |region|
      begin
        response = ec2_client(region).describe_vpc_peering_connection()
        connections = []
        response.data.vpc_peering_connections.each do |connection|
          hash = peering_connection_to_hash(region, connection)
          connections << new(hash) if has_name?(hash)
        end
        tables
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  def self.peering_connection_to_hash(region, connection)
    name = name_from_tag(connection)
    return {} unless name
    {
      name: name,
      id: connection.vpc_peering_connection_id,
      local_vpc: vpc_name_from_id(region, connection.requester_vpc_info.vpc_id)
      peer_vpc: vpc_name_from_id(region, connection.accepter_vpc_info.vpc_id)
      ensure: :present,
      region: region,
      tags: tags_for(connection),
    }
  end

  def exists?
    Puppet.info("Checking if VPC Peering Connection #{name} exists in #{target_region}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating VPC Peering Connection #{name} in #{target_region}")
    ec2 = ec2_client(target_region)

    local_vpc_response = ec2.describe_vpcs(filters: [
      {name: "tag:Name", values: [resource[:local_vpc]]},
    ])
    fail "Multiple VPCs with name #{resource[:local_vpc]}" if local_vpc_response.data.vpcs.count > 1
    fail "No VPCs with name #{resource[:local_vpc]}" if local_vpc_response.data.vpcs.empty?

    peer_vpc_response = ec2.describe_vpcs(filters: [
      {name: "tag:Name", values: [resource[:peer_vpc]]},
    ])
    fail "Multiple VPCs with name #{resource[:peer_vpc]}" if peer_vpc_response.data.vpcs.count > 1
    fail "No VPCs with name #{resource[:peer_vpc]}" if peer_vpc_response.data.vpcs.empty?

    response = ec2.create_vpc_peering_connection(
      vpc_id: local_vpc_response.data.vpcs.first.vpc_id,
      peer_vpc_id: peer_vpc_response.data.vpcs.first.vpc_id,
    )
    id = response.data.vpc_peering_connection.vpc_peering_connection_id
    with_retries(:max_tries => 5) do
      ec2.create_tags(
        resources: [id],
        tags: tags_for_resource,
      )
    end
    if resource[:auto_accept]
      ec2.accept_vpc_peering_connection(
        vpc_peering_connection_id: id,
      )
    end
    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting VPC Peering Connection #{name} in #{target_region}")
    ec2_client(target_region).delete_vpc_peering_connection(vpc_peering_connection_id: @property_hash[:id])
    @property_hash[:ensure] = :absent
  end
end
