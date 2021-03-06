require 'yaml'
require 'stax/aws/dynamodb'
require_relative 'dynamodb/throughput'
require_relative 'dynamodb/backup'

module Stax
  module DynamoDB
    def self.included(thor)
      thor.desc('dynamodb COMMAND', 'Dynamo subcommands')
      thor.subcommand(:dynamodb, Cmd::DynamoDB)
    end
  end

  module Cmd
    class DynamoDB < SubCommand
      stax_info :tables

      COLORS = {
        CREATING:  :yellow,
        UPDATING:  :yellow,
        DELETING:  :red,
        ACTIVE:    :green,
        DELETED:   :red,
        AVAILABLE: :green,
      }

      no_commands do
        def stack_tables
          Aws::Cfn.resources_by_type(my.stack_name, 'AWS::DynamoDB::Table')
        end

        ## get table names from logical IDs, return all tables if nil
        def stack_table_names(logical_ids)
          stack_tables.tap do |tables|
            tables.select! { |t| logical_ids.include?(t.logical_resource_id) } if logical_ids
          end.map(&:physical_resource_id)
        end
      end

      desc 'tables', 'list tables for stack'
      def tables
        debug("Dynamo tables for stack #{my.stack_name}")
        print_table stack_tables.map { |r|
          t = Aws::DynamoDB.table(r.physical_resource_id)
          g = Aws::DynamoDB.global_table(r.physical_resource_id)
          regions = g.nil? ? '-' : g.replication_group.map(&:region_name).sort.join(',')
          [ t.table_name, color(t.table_status, COLORS), t.item_count, t.table_size_bytes, t.creation_date_time, regions ]
        }
      end

      desc 'gsi ID', 'list global secondary indexes for table with ID'
      def gsi(id)
        print_table Aws::DynamoDB.gsi(my.resource(id)).map { |i|
          hash  = i.key_schema.find{ |k| k.key_type == 'HASH' }&.attribute_name
          range = i.key_schema.find{ |k| k.key_type == 'RANGE' }&.attribute_name
          [i.index_name, hash, range, i.projection.projection_type, i.index_size_bytes, i.item_count]
        }.sort
      end

      desc 'lsi ID', 'list local secondary indexes for table with ID'
      def lsi(id)
        print_table Aws::DynamoDB.lsi(my.resource(id)).map { |i|
          hash  = i.key_schema.find{ |k| k.key_type == 'HASH' }&.attribute_name
          range = i.key_schema.find{ |k| k.key_type == 'RANGE' }&.attribute_name
          [i.index_name, hash, range, i.projection.projection_type, i.index_size_bytes, i.item_count]
        }.sort
      end

      desc 'keys ID', 'get hash and range keys of table with ID'
      def keys(id)
        print_table Aws::DynamoDB.keys(my.resource(id))
      end

      desc 'scan ID', 'scan table with given logical id from this stack'
      def scan(id)
        Aws::DynamoDB.scan(table_name: my.resource(id))
      end

      desc 'count ID', 'count items in table with given id'
      def count(id)
        puts Aws::DynamoDB.count(table_name: my.resource(id))
      end

      desc 'query ID HASH_VALUE [RANGE_VALUE]', 'query table with id'
      def query(id, hash_value, range_value = nil)
        name = my.resource(id)
        k = Aws::DynamoDB.keys(name)
        Aws::DynamoDB.query(
          table_name: name,
          expression_attribute_values: {
            ':h' => hash_value,
            ':r' => range_value,
          }.compact,
          key_condition_expression: [
            "#{k[:hash]} = :h",
            range_value ? "#{k[:range]} = :r" : nil,
          ].compact.join(' and '),
        )
      end

      desc 'put ID', 'put items from stdin to table'
      method_option :verbose, aliases: '-v', type: :boolean, default: false, desc: 'show progress'
      def put(id)
        table = my.resource(id)
        count = 0
        $stdin.each do |line|
          Aws::DynamoDB.put(table_name: table, item: JSON.parse(line))
          print '.' if options[:verbose]
          count += 1
        end
        print "\n" if options[:verbose]
        puts "put #{count} items to #{table}"
      end

    end
  end
end