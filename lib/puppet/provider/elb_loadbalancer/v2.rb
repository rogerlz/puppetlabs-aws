require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:elb_loadbalancer).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws

  mk_resource_methods

  def self.instances
    regions.collect do |region|
      begin
        load_balancers = []
        region_client = elb_client(region)
        region_client.describe_load_balancers.each do |response|
          response.data.load_balancer_descriptions.collect do |lb|
            load_balancers << new(load_balancer_to_hash(region, lb))
          end
        end
        load_balancers
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  read_only(:region, :scheme, :availability_zones, :listeners, :instances)

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]  # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov
      end
    end
  end

  def self.load_balancer_to_hash(region, load_balancer)
    instance_ids = load_balancer.instances.map(&:instance_id)
    instance_names = []
    unless instance_ids.empty?
      instances = ec2_client(region).describe_instances(instance_ids: instance_ids).collect do |response|
        response.data.reservations.collect do |reservation|
          reservation.instances.collect do |instance|
            instance
          end
        end.flatten
      end.flatten
      instances.each do |instance|
        name_tag = instance.tags.detect { |tag| tag.key == 'Name' }
        name = name_tag ? name_tag.value : nil
        instance_names << name if name
      end
    end
    listeners = load_balancer.listener_descriptions.collect do |listener|
      {
        'protocol' => listener.listener.protocol,
        'load_balancer_port' => listener.listener.load_balancer_port,
        'instance_protocol' => listener.listener.instance_protocol,
        'instance_port' => listener.listener.instance_port,
      }
    end
    health_check = {}
    unless load_balancer.health_check.nil?
        health_check = {
          'healthy_threshold' => load_balancer.health_check.healthy_threshold,
          'interval' => load_balancer.health_check.interval,
          'target' => load_balancer.health_check.target,
          'timeout' => load_balancer.health_check.timeout,
          'unhealthy_threshold' => load_balancer.health_check.unhealthy_threshold,
        }
    end
    tag_response = elb_client(region).describe_tags(
      load_balancer_names: [load_balancer.load_balancer_name]
    )
    tags = {}
    unless tag_response.tag_descriptions.nil? || tag_response.tag_descriptions.empty?
      tag_response.tag_descriptions.first.tags.each do |tag|
        tags[tag.key] = tag.value unless tag.key == 'Name'
      end
    end
    subnet_names = []
    unless load_balancer.subnets.nil? || load_balancer.subnets.empty?
      response = ec2_client(region).describe_subnets(subnet_ids: load_balancer.subnets)
      subnet_names = response.data.subnets.collect do |subnet|
        subnet_name_tag = subnet.tags.detect { |tag| tag.key == 'Name' }
        subnet_name_tag ? subnet_name_tag.value : nil
      end.reject(&:nil?)
    end
    security_group_names = []
    unless load_balancer.security_groups.nil? || load_balancer.security_groups.empty?
      group_response = ec2_client(region).describe_security_groups(group_ids: load_balancer.security_groups)
      security_group_names = group_response.data.security_groups.collect(&:group_name)
    end
    config = {
      name: load_balancer.load_balancer_name,
      ensure: :present,
      region: region,
      availability_zones: load_balancer.availability_zones,
      instances: instance_names,
      listeners: listeners,
      tags: tags,
      subnets: subnet_names,
      security_groups: security_group_names,
      scheme: load_balancer.scheme,
      health_check: health_check,
    }
    if load_balancer.respond_to?('dns_name') && !load_balancer.dns_name.nil?
      config[:endpoint] = load_balancer.dns_name
    end
    config
  end

  def exists?
    Puppet.info("Checking if load balancer #{name} exists in region #{target_region}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating load balancer #{name} in region #{target_region}")
    subnets = subnet_ids_from_names(resource[:subnets])
    security_groups = security_group_ids_from_names(resource[:security_groups])
    zones = resource[:availability_zones]
    zones = [zones] unless zones.is_a?(Array)

    tags = resource[:tags] ? resource[:tags].map { |k,v| {key: k, value: v} } : []
    tags << {key: 'Name', value: name}

    listeners = resource[:listeners]
    listeners = [listeners] unless listeners.is_a?(Array)

    listeners_for_api = listeners.collect do |listener|
      {
        protocol: listener['protocol'],
        load_balancer_port: listener['load_balancer_port'],
        instance_protocol: listener['instanceprotocol'],
        instance_port: listener['instance_port'],
      }
    end

    elb_client(target_region).create_load_balancer(
      load_balancer_name: name,
      listeners: listeners_for_api,
      availability_zones: zones,
      security_groups: security_groups,
      subnets: subnets,
      scheme: resource['scheme'],
      tags: tags_for_resource,
    )

    @property_hash[:ensure] = :present

    if ! resource[:health_check].nil?
      self.health_check = resource[:health_check]
    end
  end

  def security_group_ids_from_names(names)
    unless names.nil? || names.empty?
      vpc_id = if resource[:subnets]
        subnets = resource[:subnets]
        subnets = [subnets] unless subnets.is_a?(Array)
        vpc_id_from_subnet_name(subnets.first)
      else
        nil
      end

      filters = [{name: 'group-name', values: names}]
      filters << {name: 'vpc-id', values: [vpc_id]} if vpc_id

      names = [names] unless names.is_a?(Array)
      response = ec2_client(resource[:region]).describe_security_groups(filters: filters)
      response.data.security_groups.map(&:group_id)
    else
      []
    end
  end

  def vpc_id_from_subnet_name(name)
    response = ec2_client(resource[:region]).describe_subnets(filters: [
      {name: 'tag:Name', values: [name]}
    ])
    fail("No subnet with name #{name}") if response.data.subnets.empty?
    response.data.subnets.map(&:vpc_id).first
  end

  def subnet_ids_from_names(names)
    unless names.empty?
      names = [names] unless names.is_a?(Array)
      response = ec2_client(resource[:region]).describe_subnets(filters: [
        {name: 'tag:Name', values: names}
      ])
      response.data.subnets.map(&:subnet_id)
    else
      []
    end
  end

  def security_groups=(value)
    unless value.empty?
      ids = security_group_ids_from_names(value)
      elb_client(resource[:region]).apply_security_groups_to_load_balancer(
        load_balancer_name: name,
        security_groups: ids,
      ) unless ids.empty?
    end
  end

  def subnets=(value)
    to_create = value - @property_hash[:subnets]
    to_delete = @property_hash[:subnets] - value
    elb = elb_client(resource[:region])
    unless to_delete.empty?
      delete_ids = subnet_ids_from_names(to_delete)
      elb.detach_load_balancer_from_subnets(
        load_balancer_name: name,
        subnets: delete_ids,
      )
    end
    unless to_create.empty?
      create_ids = subnet_ids_from_names(to_create)
      elb.attach_load_balancer_to_subnets(
        load_balancer_name: name,
        subnets: create_ids,
      )
    end
  end

  def health_check=(value)
    elb = elb_client(resource[:region])
    elb.configure_health_check({
      load_balancer_name: name,
      health_check: {
        target: value['target'],
        interval: value['interval'],
        timeout: value['timeout'],
        unhealthy_threshold: value['unhealthy_threshold'],
        healthy_threshold: value['healthy_threshold'],
      },
    })
  end

  def tags=(value)
     Puppet.info("Updating tags for #{name} in region #{target_region}")
     elb = elb_client(resource[:region])
     elb.add_tags(
       load_balancer_names: [@property_hash[:name]],
       tags: value.collect { |k,v| { :key => k, :value => v } }
     ) unless value.empty?
     missing_tags = tags.keys - value.keys
     elb.remove_tags(
       load_balancer_names: [@property_hash[:name]],
       tags: missing_tags.collect { |k| { :key => k } }
     ) unless missing_tags.empty?
  end

  def destroy
    Puppet.info("Destroying load balancer #{name} in region #{target_region}")
    elb_client(target_region).delete_load_balancer(
      load_balancer_name: name,
    )
    @property_hash[:ensure] = :absent
  end
end
