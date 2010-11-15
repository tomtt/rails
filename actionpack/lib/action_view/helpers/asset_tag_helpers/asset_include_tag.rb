require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/file'
require 'action_view/helpers/tag_helper'
require 'action_view/helpers/asset_tag_helpers/common_asset_helpers'
require 'action_view/helpers/asset_tag_helpers/asset_id_caching'


module ActionView
  module Helpers
    module AssetTagHelper

      class AssetIncludeTag
        include CommonAssetHelpers
        include AssetIdCaching

        attr_reader :config, :controller

        class_attribute :expansions
        self.expansions = { }

        def initialize(config, controller)
          @config = config
          @controller = controller
        end

        def asset_name
          raise NotImplementedError
        end

        def extension
          raise NotImplementedError
        end

        def custom_dir
          raise NotImplementedError
        end

        def asset_tag(source, options)
          raise NotImplementedError
        end

        def include_tag(*sources)
          options = sources.extract_options!.stringify_keys
          concat  = options.delete("concat")
          cache   = concat || options.delete("cache")
          recursive = options.delete("recursive")

          if concat || (config.perform_caching && cache)
            joined_name = (cache == true ? "all" : cache) + ".#{extension}"
            joined_path = File.join((joined_name[/^#{File::SEPARATOR}/] ? config.assets_dir : custom_dir), joined_name)
            unless config.perform_caching && File.exists?(joined_path)
              write_asset_file_contents(joined_path, compute_paths(sources, recursive))
            end
            asset_tag(joined_name, options)
          else
            sources = expand_sources(sources, recursive)
            ensure_sources!(sources) if cache
            sources.collect { |source| asset_tag(source, options) }.join("\n").html_safe
          end
        end


        private

          def path_to_asset(source)
            compute_public_path(source, asset_name.to_s.pluralize, extension)
          end

          def compute_paths(*args)
            expand_sources(*args).collect { |source| compute_public_path(source, asset_name.pluralize, extension, false) }
          end

          def expand_sources(sources, recursive)
            if sources.first == :all
              collect_asset_files(custom_dir, ('**' if recursive), "*.#{extension}")
            else
              sources.collect do |source|
                determine_source(source, expansions)
              end.flatten
            end
          end

          def ensure_sources!(sources)
            sources.each do |source|
              asset_file_path!(compute_public_path(source, asset_name.pluralize, extension))
            end
            return sources
          end

          def collect_asset_files(*path)
            dir = path.first

            Dir[File.join(*path.compact)].collect do |file|
              file[-(file.size - dir.size - 1)..-1].sub(/\.\w+$/, '')
            end.sort
          end

          def determine_source(source, collection)
            case source
            when Symbol
              collection[source] || raise(ArgumentError, "No expansion found for #{source.inspect}")
            else
              source
            end
          end

          def join_asset_file_contents(paths)
            paths.collect { |path| File.read(asset_file_path!(path, true)) }.join("\n\n")
          end

          def write_asset_file_contents(joined_asset_path, asset_paths)
            FileUtils.mkdir_p(File.dirname(joined_asset_path))
            File.atomic_write(joined_asset_path) { |cache| cache.write(join_asset_file_contents(asset_paths)) }

            # Set mtime to the latest of the combined files to allow for
            # consistent ETag without a shared filesystem.
            mt = asset_paths.map { |p| File.mtime(asset_file_path(p)) }.max
            File.utime(mt, mt, joined_asset_path)
          end

          def asset_file_path(path)
            File.join(config.assets_dir, path.split('?').first)
          end

          def asset_file_path!(path, error_if_file_is_uri = false)
            if is_uri?(path)
              raise(Errno::ENOENT, "Asset file #{path} is uri and cannot be merged into single file") if error_if_file_is_uri
            else
              absolute_path = asset_file_path(path)
              raise(Errno::ENOENT, "Asset file not found at '#{absolute_path}'" ) unless File.exist?(absolute_path)
              return absolute_path
            end
          end
      end

    end
  end
end