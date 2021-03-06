require 'json'
require 'contentful/management'
require 'contentful/bootstrap/templates/links/base'

module Contentful
  module Bootstrap
    module Templates
      class Base
        attr_reader :space, :skip_content_types

        def initialize(space, quiet = false, skip_content_types = false)
          @space = space
          @quiet = quiet
          @skip_content_types = skip_content_types
        end

        def run
          create_content_types unless skip_content_types
          create_assets
          create_entries

          after_run
        rescue Contentful::Management::Error => e
          error = e.error
          output "Error at: #{error[:url]}"
          output "Message: #{error[:message]}"
          output "Details: #{error[:details]}"

          raise e
        end

        def content_types
          []
        end

        def entries
          {}
        end

        def assets
          []
        end

        def after_run
        end

        protected

        def output(text = nil)
          Support.output(text, @quiet)
        end

        def create_file(name, url, properties = {})
          image = Contentful::Management::File.new
          image.properties[:contentType] = properties.fetch(:contentType, 'image/jpeg')
          image.properties[:fileName] = "#{name}"
          image.properties[:upload] = url
          image
        end

        private

        def create_content_types
          content_types.each do |ct|
            begin
              output "Creating Content Type '#{ct['name']}'"

              fields = []
              content_type = space.content_types.new
              content_type.id = ct['id']
              content_type.name = ct['name']
              content_type.display_field = ct['displayField']
              content_type.description = ct['description']

              ct['fields'].each do |f|
                field = Contentful::Management::Field.new
                field.id = f['id']
                field.name = f['name']
                field.type = f['type']
                field.link_type = f['linkType'] if link?(f)

                if array?(f)
                  array_field = Contentful::Management::Field.new
                  array_field.type = f['items']['type']
                  array_field.link_type = f['items']['linkType']
                  field.items = array_field
                end

                fields << field
              end

              content_type.fields = fields
              content_type.save
              content_type.activate
            rescue Contentful::Management::Conflict
              output "ContentType '#{ct['id']}' already created! Skipping"
              next
            end
          end
        end

        def link?(field)
          field.key?('linkType')
        end

        def array?(field)
          field.key?('items')
        end

        def create_assets
          assets.each do |asset|
            begin
              output "Creating Asset '#{asset['title']}'"
              asset = space.assets.create(
                id: asset['id'],
                title: asset['title'],
                file: asset['file']
              )
              asset.process_file

              attempts = 0
              while attempts < 10
                unless space.assets.find(asset.id).file.url.nil?
                  asset.publish
                  break
                end

                sleep(1) # Wait for Process
                attempts += 1
              end
            rescue Contentful::Management::Conflict
              output "Asset '#{asset['id']}' already created! Skipping"
              next
            end
          end
        end

        def create_entries
          content_types = []
          processed_entries = entries.map do |content_type_id, entry_list|
            content_type = space.content_types.find(content_type_id)
            content_types << content_type

            entry_list.each.map do |e|
              array_fields = []
              regular_fields = []
              e.each do |field_name, value|
                if value.is_a? ::Array
                  array_fields << field_name
                  next
                end

                regular_fields << field_name
              end

              array_fields.each do |af|
                e[af].map! do |item|
                  if item.is_a? ::Contentful::Bootstrap::Templates::Links::Base
                    item.to_management_object
                  else
                    item
                  end
                end
                e[af.to_sym] = e.delete(af)
              end

              regular_fields.each do |rf|
                value = e.delete(rf)
                if value.is_a? ::Contentful::Bootstrap::Templates::Links::Base
                  value = value.to_management_object
                end
                e[rf.to_sym] = value
              end

              begin
                output "Creating Entry #{e[:id]}"
                entry = content_type.entries.create({:id => e[:id]})
                entry.save

                e = e.clone
                e[:id] = entry.id # in case no ID was specified in template
              rescue Contentful::Management::Conflict
                output "Entry '#{e[:id]}' already exists! Skipping"
              ensure
                next e
              end
            end
          end.flatten

          processed_entries = processed_entries.map do |e|
            output "Populating Entry #{e[:id]}"

            entry = space.entries.find(e[:id])
            e.delete(:id)
            entry.update(e)
            entry.save

            10.times do
              break if space.entries.find(entry.id).sys[:version] >= 4
              sleep(0.5)
            end

            entry.id
          end

          processed_entries.each { |e| space.entries.find(e).publish }
        end
      end
    end
  end
end
