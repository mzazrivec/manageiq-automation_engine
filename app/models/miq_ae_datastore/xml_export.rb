require "builder"

module MiqAeDatastore
  class XmlExport
    include Vmdb::Logging
    def self.to_xml
      _log.info("Exporting to XML")
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!
      xml.MiqAeDatastore(:version => '1.0') do
        MiqAeClass.all.sort_by(&:fqname).each do |miq_ae_class|
          miq_ae_class.to_export_xml(:builder => xml, :skip_instruct => true, :indent => 2)
        end
        CustomButton.all.each do |custom_button|
          custom_button.to_export_xml(:builder => xml, :skip_instruct => true, :indent => 2)
        end
      end
    end

    def self.class_to_xml(namespace, class_name)
      _log.info("Exporting class: #{class_name} to XML")
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!
      xml.MiqAeDatastore(:version => '1.0') do
        c = MiqAeClass.lookup_by_namespace_and_name(namespace, class_name)
        c.to_export_xml(:builder => xml, :skip_instruct => true, :indent => 2)
      end
    end

    def self.export_sub_namespaces(namespace, xml)
      namespace.ae_namespaces.each do |n|
        sn = MiqAeNamespace.lookup_by_fqname(n.fqname)
        export_all_classes_for_namespace(sn, xml)
        export_sub_namespaces(sn, xml)
      end
    end

    def self.namespace_to_xml(namespace)
      _log.info("Exporting namespace: #{namespace} to XML")
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!
      rec = MiqAeNamespace.lookup_by_fqname(namespace)
      if rec.nil?
        _log.info("Namespace:  <#{namespace}> not found.")
        return nil
      end

      xml.MiqAeDatastore(:version => '1.0') do
        export_all_classes_for_namespace(rec, xml)
        export_sub_namespaces(rec, xml)
      end
    end

    def self.export_all_classes_for_namespace(namespace, xml)
      MiqAeClass.where(:namespace_id => namespace.id.to_i).sort_by(&:fqname).each do |c|
        c.to_export_xml(:builder => xml, :skip_instruct => true, :indent => 2)
      end
    end
  end
end
