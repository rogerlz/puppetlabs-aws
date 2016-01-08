require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:ec2_vpc_route_entry).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods

  def self.instances
    regions.collect do |region|
      begin
        response = ec2_client(region).describe_route_table()
        table = []
        response.data.route_tables.each do |table|
          hash = route_table_to_hash(region, table)
          tables << new(hash) if has_name?(hash)
        end
        tables
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  # FIXME should support route edit
  #def self.route_to_hash(region, route)
  #  gateway_name = route.state == 'active' ? gateway_name_from_id(region, route.gateway_id) : nil
  #  hash = {
  #    'destination_cidr_block' => route.destination_cidr_block,
  #    'gateway' => gateway_name,
  #  }
  #  gateway_name.nil? ? nil : hash
  #end

  def self.route_to_hash(region, route)
    # FIXME
    #routes = table.routes.collect do |route|
    #  route_to_hash(region, route)
    #end.compact
    {
      name: name,
      id: table.route_table_id,
      vpc: vpc_name_from_id(region, table.vpc_id),
      ensure: :present,
      #routes: routes,
      region: region,
      tags: tags_for(table),
    }
  end

  def exists?
    Puppet.info("Checking if Route entry #{destination_cidr_block} exists in #{route_table}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating Route entry #{destination_cidr_block} in #{route_table}")
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

    unless found_vpn_gateway
      # lookup for peering_connection
      peering_connection_response = ec2.describe_vpc_peering_connection(filters: [
        {name: 'tag:Name', values: [gateway]},
      ])
      found_peering_connection = !peering_connection_response.data.vpc_peering_connections.empty?
    end

      gateway_id = if found_internet_gateway
                     internet_gateway_response.data.internet_gateways.first.internet_gateway_id
                   elsif found_vpn_gateway
                     vpn_gateway_response.data.vpn_gateways.first.vpn_gateway_id
                   else
                     nil
                   end

      peering_id  = if not gateway_id and found_peering_connection
                      found_peering_connection.data.vpc_peering_connections.first.vpc_peering_connection_id
                    else
                      nil
                    end

      ec2.create_route(
        route_table_id: id,
        destination_cidr_block: route['destination_cidr_block'],
        gateway_id: gateway_id,
      ) if gateway_id

      ec2_create_route(
        route_table_id: id,
        destination_cidr_block: route['destination_cidr_block'],
        vpc_peering_connection_id: peering_id,
      ) if peering_id


    end
    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting Route entry #{destination_cidr_block} in #{route_table}")
    ec2_client(target_region).delete_route(
      route_table_id:
      destination_cidr_block: @property_hash[:destination_cidr_block]
    )
    @property_hash[:ensure] = :absent
  end
end
