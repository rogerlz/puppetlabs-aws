require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:ec2_vpc_routetable_route).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods

  def self.instances
    regions.collect do |region|
      begin
        response = ec2_client(region).describe_route_tables()
        tables = []
        response.data.route_tables.each do |table|
          table.routes.collect do |route|
            hash = route_to_hash(region, route, table)
            tables << new(hash) if has_name?(hash)
          end
        end
        tables
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  read_only(:region)

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  def self.route_to_hash(region, route, table)
    name = name_from_tag(table)
    return {} unless name
    return {} unless route.state == 'active'

    # igw/vpn
    unless route.gateway_id.nil?
      gateway_name = gateway_name_from_id(region, route.gateway_id)
    end

    # vpc peering
    unless gateway_name && route.vpc_peering_connection_id.nil?
      gateway_name = vpc_peering_name_from_id(region, route.vpc_peering_connection_id)
    end

    # nat gw
    unless gateway_name && route.nat_gateway_id.nil?
      gateway_name = route.nat_gateway_id
    end

    # instance_id
    if !gateway_name && !route.instance_id.nil?
      ec2_client(region).describe_instances(instance_ids: [route.instance_id]).collect do |response2|
        response2.data.reservations.collect do |reservation|
          hash = reservation.instances.collect do |instance|
            name_tag = instance.tags.detect { |tag| tag.key == 'Name' }
            gateway_name = name_tag.value
          end
        end
      end
    end

    {
      name: "#{name}:#{route.destination_cidr_block}",
      ensure: :present,
      region: region,
      routetable_name: name,
      routetable_id: table.route_table_id,
      destination_cidr_block: route.destination_cidr_block,
      gateway: gateway_name,
    }
  end

  def exists?
    Puppet.info("Checking if Route entry #{region} exists in #{routetable_name}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating Route entry #{destination_cidr_block} in #{routetable_name}")
    ec2 = ec2_client(target_region)

    gateway = resource[:gateway]

    internet_gateway_response = ec2.describe_internet_gateways(filters: [
      {name: 'tag:Name', values: [gateway]},
    ])
    found_internet_gateway = !internet_gateway_response.data.internet_gateways.empty?

    unless found_internet_gateway
      vpn_gateway_response = ec2.describe_vpn_gateways(filters: [
        {name: 'tag:Name', values: [gateway]},
      ])
      found_vpn_gateway = !vpn_gateway_response.data.vpn_gateways.empty?
    end

    #unless found_vpn_gateway
    #  # lookup for peering_connection
    #  peering_connection_response = ec2.describe_vpc_peering_connection(filters: [
    #    {name: 'tag:Name', values: [gateway]},
    #  ])
    #  found_peering_connection = !peering_connection_response.data.vpc_peering_connections.empty?
    #end

    gateway_id = if found_internet_gateway
                   internet_gateway_response.data.internet_gateways.first.internet_gateway_id
                 elsif found_vpn_gateway
                   vpn_gateway_response.data.vpn_gateways.first.vpn_gateway_id
                 else
                   nil
                 end

    #peering_id  = if not gateway_id and found_peering_connection
    #                found_peering_connection.data.vpc_peering_connections.first.vpc_peering_connection_id
    #              else
    #                nil
    #              end

    ec2.create_route(
      route_table_id: id,
      destination_cidr_block: route['destination_cidr_block'],
      gateway_id: gateway_id,
      # vpc_peering_connection_id: peering_id,
      # instance_id,
      # nat_gateway_id,
    ) if gateway_id

    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting Route entry #{destination_cidr_block} in #{route_table}")

    ec2_client(target_region).delete_route(
      route_table_id: routetable_id,
      destination_cidr_block: @property_hash[:destination_cidr_block]
    )
    @property_hash[:ensure] = :absent
  end

end
