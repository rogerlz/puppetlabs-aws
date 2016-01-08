require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:rds_db_subnet_group).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws

  mk_resource_methods

  def self.instances
    regions.collect do |region|
      instances = []
      rds_client(region).describe_db_subnet_groups.each do |response|
        response.data.db_subnet_groups.each do |db_subnet_group|
          # There's always a default class
          unless db_subnet_group.db_subnet_group_name =~ /^default$/
            hash = db_subnet_group_to_hash(region, db_subnet_group)
            instances << new(hash) if hash[:name]
          end
        end
      end
      instances
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  read_only(:region, :description)

  def self.db_subnet_group_to_hash(region, db_subnet_group)
#    subnet_names = []
#    unless db_subnet_group.subnets.nil? || db_subnet_group.subnets.empty?
#      Puppet.debug("#{db_subnet_group.subnets}")
#      response = ec2_client(region).describe_subnets(subnet_ids: db_subnet_group.subnets)
#      Puppet.debug(response)
#      subnet_names = response.data.subnets.collect do |subnet|
#        subnet_name_tag = subnet.tags.detect { |tag| tag.key == 'Name' }
#        subnet_name_tag ? subnet_name_tag.value : nil
#      end.reject(&:nil?)
#    end

    {
      :ensure => :present,
      :region => region,
      :name => db_subnet_group.db_subnet_group_name,
      :description => db_subnet_group.db_subnet_group_description,
#      :subnets => subnet_names,
    }
  end

  def exists?
    Puppet.info("Checking if DB Subnet Group #{name} exists")
    [:present, :creating, :available].include? @property_hash[:ensure]
  end

  def create
    Puppet.info("Creating DB Subnet Group #{name}")
    subnets = subnet_ids_from_names(resource[:subnets])
    config = {
      :db_subnet_group_name        => resource[:name],
      :db_subnet_group_description => resource[:description],
      :subnet_ids                  => subnets,
    }

    rds_client(resource[:region]).create_db_subnet_group(config)

    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting DB Subnet Group #{name} in region #{resource[:region]}")
    rds = rds_client(resource[:region])
    config = {
      db_subnet_group_name: name,
    }
    rds.delete_db_subnet_group(config)
    @property_hash[:ensure] = :absent
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

end
