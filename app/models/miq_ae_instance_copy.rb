class MiqAeInstanceCopy
  attr_accessor :flags
  include MiqAeCopyMixin
  DELETE_PROPERTIES = %w[id instance_id field_id updated_on created_on
                         updated_by updated_by_user_id].freeze

  def initialize(instance_fqname, validate_schema = true)
    @src_domain, @partial_ns, @ae_class, @instance_name = MiqAeInstanceCopy.split(instance_fqname, true)
    @class_fqname = "#{@src_domain}/#{@partial_ns}/#{@ae_class}"
    @src_class = MiqAeClass.lookup_by_fqname("#{@src_domain}/#{@partial_ns}/#{@ae_class}")
    raise "Source class not found #{@class_fqname}" unless @src_class

    @src_instance = MiqAeInstance.find_by(:name => @instance_name, :class_id => @src_class.id)
    raise "Source instance #{@instance_name} not found #{@class_fqname}" unless @src_instance

    @target_class_name = @ae_class
    @flags = MiqAeClassCompareFields::CONGRUENT_SCHEMA | MiqAeClassCompareFields::COMPATIBLE_SCHEMA
    @validate_schema = validate_schema
  end

  def to_domain(domain, namespace = nil, overwrite = false)
    check_duplicity(domain, namespace, @instance_name)
    @overwrite        = overwrite
    @target_ns        = namespace.nil? ? @partial_ns : namespace
    @target_name      = @instance_name
    @target_domain    = domain
    copy
  end

  def as(new_name, namespace = nil, overwrite = false)
    check_duplicity(@src_domain, namespace, new_name)
    @overwrite        = overwrite
    @target_ns        = namespace.nil? ? @partial_ns : namespace
    @target_name      = new_name
    @target_domain    = @src_domain
    copy
  end

  def self.copy_multiple(ids, domain, namespace = nil, overwrite = false)
    validate_flag = true
    nids = []
    MiqAeInstance.transaction do
      ids.each do |id|
        instance_obj = MiqAeInstance.find(id)
        new_instance = new(instance_obj.fqname, validate_flag).to_domain(domain, namespace, overwrite)
        nids << new_instance.id if new_instance
        validate_flag = false
      end
    end
    nids
  end

  private

  def find_or_create_class
    @dest_class = MiqAeClass.lookup_by_fqname("#{@target_domain}/#{@target_ns}/#{@target_class_name}")
    return unless @dest_class.nil?

    @dest_class = MiqAeClassCopy.new(@class_fqname).to_domain(@target_domain, @target_ns)
  end

  def copy
    validate
    create_instance
    @dest_instance.ae_values << add_values
    @dest_instance.save!
    @dest_instance
  end

  def add_values
    @src_instance.ae_values.collect do |v|
      attrs = v.attributes.delete_if { |k, _| DELETE_PROPERTIES.include?(k) }
      field_id = get_new_field_id(v.field_id)
      next if field_id.nil?

      MiqAeValue.new({:field_id => field_id}.merge(attrs))
    end.compact
  end

  def get_new_field_id(field_id)
    src_field = @src_class.ae_fields.detect { |f| f.id == field_id }
    raise "Field id #{field_id} not found in source class #{@src_class.name}" if src_field.nil?

    dest_field = @dest_class.ae_fields.detect { |f| f.name == src_field.name }
    return nil if dest_field.nil? && (@class_schema_status & @flags).positive?
    raise "Field name #{src_field.name} not found in target class #{@dest_class.name}" if dest_field.nil?

    dest_field.id
  end

  def create_instance
    @dest_instance = MiqAeInstance.find_by(:class_id => @dest_class.id, :name => @target_name)
    if @dest_instance
      @dest_instance.destroy if @overwrite
      raise "Instance #{@target_name} exists in #{@target_ns_fqname} class #{@target_class_name}" unless @overwrite
    end
    @dest_instance = MiqAeInstance.create!(:name         => @target_name,
                                           :description  => @src_instance.description,
                                           :display_name => @src_instance.display_name,
                                           :inherits     => @src_instance.inherits,
                                           :class_id     => @dest_class.id)
  end

  def validate
    find_or_create_class
    return unless @validate_schema

    @class_schema_status = MiqAeClassCompareFields.new(@src_class, @dest_class).compare
    raise "Instance cannot be copied, automation class schema mismatch" if (@flags & @class_schema_status).zero?
  end

  def check_duplicity(domain, namespace, instance_name)
    if domain.downcase == @src_domain.downcase && instance_name.downcase == @instance_name.downcase
      raise "Cannot copy instance onto itself" if namespace.nil? || namespace.downcase == @partial_ns.downcase
    end
  end
end
