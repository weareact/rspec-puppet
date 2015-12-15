module RSpec::Puppet
  class Coverage

    attr_accessor :filters

    class << self
      extend Forwardable
      def_delegators(:instance, :add, :cover!, :report!,
                     :filters, :add_filter, :add_from_catalog)
    end

    include Singleton

    def initialize
      @collection = {}
      @filters = ['Stage[main]', 'Class[Settings]', 'Class[main]']
    end

    def add(resource)
      if !exists?(resource) && !filtered?(resource)
        @collection[resource.to_s] = ResourceWrapper.new(resource)
      end
    end

    def add_filter(type, title)
      @filters << "#{type.capitalize}[#{title.capitalize}]"
    end

    # add all resources from catalog declared in module test_module
    def add_from_catalog(catalog, test_module)
      coverable_resources = catalog.to_a.select { |resource| !filter_resource?(resource, test_module) }
      coverable_resources.each do |resource|
        add(resource)
      end
    end

    def filtered?(resource)
      filters.include?(resource.to_s)
    end

    def cover!(resource)
      if !filtered?(resource) && (wrapper = find(resource))
        wrapper.touch!
      end
    end

    def report!
      report = {}

      report[:total] = @collection.size
      report[:touched] = @collection.count { |_, resource| resource.touched? }
      report[:untouched] = report[:total] - report[:touched]
      report[:coverage] = sprintf("%5.2f", ((report[:touched].to_f/report[:total].to_f)*100))

      report[:detailed] = Hash[*@collection.map do |name, wrapper|
        [name, wrapper.to_hash]
      end.flatten]

      puts <<-EOH.gsub(/^ {8}/, '')

        Total resources:   #{report[:total]}
        Touched resources: #{report[:touched]}
        Resource coverage: #{report[:coverage]}%
      EOH

      if report[:coverage] != "100.00"
        puts <<-EOH.gsub(/^ {10}/, '')
          Untouched resources:

          #{
            untouched_resources = report[:detailed].reject do |_,rsrc|
              rsrc["touched"]
            end
            untouched_resources.inject([]) do |memo, (name,_)|
              memo << "  #{name}"
            end.sort.join("\n")
          }
        EOH
      end

    end

    private

    # Should this resource be excluded from coverage reports?
    #
    # The resource is not included in coverage reports if any of the conditions hold:
    #
    #   * The resource has been explicitly filtered out.
    #     * Examples: autogenerated resources such as 'Stage[main]'
    #   * The resource is a class but does not belong to the module under test.
    #     * Examples: Class dependencies included from a fixture module
    #   * The resource was declared in a file outside of the test module or site.pp
    #     * Examples: Resources declared in a dependency of this module.
    #
    # @param resource [Puppet::Resource] The resource that may be filtered
    # @param test_module [String] The name of the module under test
    # @return [true, false]
    def filter_resource?(resource, test_module)
      if @filters.include?(resource.to_s)
        return true
      end

      if resource.type == 'Class'
        module_name = resource.title.split('::').first.downcase
        if module_name != test_module
          return true
        end
      end

      if resource.file
        paths = module_paths(test_module)
        unless paths.any? { |path| resource.file.include?(path) }
          return true
        end
      end

      return false
    end

    # Find all paths that may contain testable resources for a module.
    #
    # @return [Array<String>]
    def module_paths(test_module)
      if Puppet.version.to_f >= 4.0
        modulepath = RSpec.configuration.module_path || File.join(Puppet[:environmentpath], 'fixtures', 'modules')
        manifest = RSpec.configuration.manifest || File.join(Puppet[:environmentpath], 'fixtures', 'manifests', 'site.pp')
        paths = [File.join(modulepath, test_module, 'manifests'), manifest]
      else
        paths = Puppet[:modulepath].split(File::PATH_SEPARATOR).map do |dir|
          File.join(dir, test_module, 'manifests')
        end
        paths << Puppet[:manifest]
      end
      paths
    end

    def find(resource)
      @collection[resource.to_s]
    end

    def exists?(resource)
      !find(resource).nil?
    end

    class ResourceWrapper
      attr_reader :resource

      def initialize(resource = nil)
        @resource = resource
      end

      def to_s
        @resource.to_s
      end

      def to_hash
        {
          'touched' => touched?,
        }
      end

      def touch!
        @touched = true
      end

      def touched?
        !!@touched
      end
    end
  end
end
