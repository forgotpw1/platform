require 'v1/schema'
require 'active_support/core_ext'

module V1

  module Searchable

    module Query

      def self.build_all(search, params)
        # Returns boolean for "did we run any queries?"
        field_queries = field_queries(params)
        temporal_queries = temporal_queries(params)

        # Only call search.query.boolean if we have some queries to pass it.
        # Otherwise we'll get incorrect search results.
        return false if (field_queries.empty? && temporal_queries.empty?)

        search.query do |query|
          query.boolean do |boolean|

            field_queries.each do |query_string|
              boolean.must do |must|
                #                must.string query_string
                #works                must.string "banana", 'default_field' => 'description'
                #TODO: support field-specific boost ala "fields" : ["name^5"]
                foo = [params['q'], 'fields' => ['title', 'subject.name']]
                foo = [params['q']]                
                must.string *query_string
              end
            end

            temporal_queries.each do |temporal|
              boolean.must do |must|
                must.range(*temporal)
              end
            end

          end
        end
        true
      end

      def self.field_queries(params)
        seen_date_ranges = []
        query_strings = []
        params.each do |field, value|
          next if value.blank?

          if field == 'q'
            query_strings << value
          elsif field =~ /^(created)\.(before|after)$/
            if !seen_date_ranges.include? $1
              query_strings << build_date_range_queries($1, params)
              # remember field so we don't doubledip it with the other end of the range
              seen_date_ranges << $1
            end
          else
            mapping = V1::Schema.item_mapping(field)
            next if mapping.nil?  #skip unmapped fields, including spatial.distance
            # temporal.after and created.after won't have a mapping, and are handled elsewhere

            #BUG: The $field:$value field query breaks when $value contains a colon
            # subfield search
            if field =~ /(.+)\.(.+)/
              next if mapping[:type] == 'geo_point'  #build geo search elsewhere
              next if $2 =~ /^(before|after)$/  #build range elsewhere
              query_strings << [value, 'fields' => [field]]
            else
              fields_attr = mapping['properties'].present? ? "#{field}.*" : field
              query_strings << [value, 'fields' => [fields_attr]]
            end
          end
        end

        query_strings.map {|q| Array.wrap(q)}
      end
      
      def self.build_date_range_queries(field, params)
        if params.keys.include?("#{field}.before") || params.keys.include?("#{field}.after")
          after = params["#{field}.after"].presence || '*'
          before = params["#{field}.before"].presence || '*'
          # Inclusive range queries: square brackets. Exclusive range queries: curly brackets.
          ["[#{after} TO #{before}]", 'fields' => [field]]
        end
      end

      def self.temporal_queries(params)
        #TODO: test
        ranges = []
        if params['temporal.after']
          limits = { :gte => params['temporal.after'] }
          # uncomment the below to enforce a strict "between" query rather than the
          # the default "if there is any overlap in timeframes" we use now.
          #limits[:lte] = params['temporal.before'] if params['temporal.before']
          ranges << ['temporal.end', limits]
        end
        if params['temporal.before']
          limits = { :lte => params['temporal.before'] }
          # see above "between" comment
          #limits[:gte] = params['temporal.after'] if params['temporal.after']
          ranges << ['temporal.start', limits]
        end
        ranges
      end

      # def self.build_temporal_query(search, params)
      #   memo << lambda do |boolean|
      #     boolean.must do |must|
      #       must.range(*range)
      #     end
      #   end
      #   memo
      # end

    end

  end

end
