require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:elb_loadbalancer_member).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws

  mk_resource_methods

  def self.instances
    regions.collect do |region|
      begin
        load_balancers = []
        region_client = elb_client(region)
        region_client.describe_load_balancers.each do |response|
          response.data.load_balancer_descriptions.each do |lb|
            lb_name = lb.load_balancer_name
            instance_ids = lb.instances.map(&:instance_id)
            unless instance_ids.empty?
              instances = ec2_client(region).describe_instances(instance_ids: instance_ids).collect do |response2|
                response2.data.reservations.collect do |reservation|
                  hash = reservation.instances.collect do |instance|
                    name_tag = instance.tags.detect { |tag| tag.key == 'Name' }
                    instance_name = name_tag.value
                    resource_name = "#{lb_name}:#{instance_name}"
                    hash = {
                      name: resource_name,
                      ensure: :present,
                      region: region,
                    }
                    load_balancers << new(hash)
                  end
                end
              end
            end
          end
        end
        load_balancers
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  read_only(:region)

  def exists?
    ec2_name = resource[:name].split(':')[1]
    elb_name = resource[:name].split(':')[0]

    Puppet.debug("Aws::Elb_instance_member -> Checking if instance #{ec2_name} is in load balancer #{elb_name} exists in region #{target_region}")

    response = elb_client(region).describe_load_balancers(
      load_balancer_names: [elb_name]
    )

    instance_ids = response.data.load_balancer_descriptions[0].instances.map(&:instance_id)
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

    instance_names.include? ec2_name
  end

  def create
    ec2_name = resource[:name].split(':')[1]
    elb_name = resource[:name].split(':')[0]

    Puppet.debug("Aws::Elb_instance_member -> Adding instance #{ec2_name} to load balancer #{elb_name} in region #{target_region}")

    instance_id = ec2_instance_ids_from_name(ec2_name)

    elb_client(region).register_instances_with_load_balancer(
      load_balancer_name: elb_name,
      instances: instance_id
    )

    @property_hash[:ensure] = :present
  end

  def destroy
    ec2_name = resource[:name].split(':')[1]
    elb_name = resource[:name].split(':')[0]

    instance_id = ec2_instance_ids_from_name(ec2_name)

    Puppet.debug("Aws::Elb_instance_member -> Removing instance #{ec2_name} from load balancer #{elb_name} in region #{target_region}")
    elb_client(target_region).deregister_instances_from_load_balancer(
      load_balancer_name: elb_name,
      instances: instance_id
    )
    @property_hash[:ensure] = :absent
  end

  def ec2_instance_ids_from_name(names)
    unless names.nil? || names.empty?
      names = [names] unless names.is_a?(Array)
    else
      nil
    end

    response = ec2_client(resource[:region]).describe_instances(
      filters: [
        {name: 'tag:Name', values: names},
        {name: 'instance-state-name', values: ['pending', 'running']}
      ]
    )

    instance_id = response.reservations.map(&:instances).flatten.map(&:instance_id)
    instance_input = instance_id.collect do |id|
        { instance_id: id }
    end
    instance_input
  end
end
