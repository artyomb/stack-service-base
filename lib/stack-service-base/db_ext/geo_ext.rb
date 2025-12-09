require 'rgeo'
require 'rgeo/geo_json'

unless RGeo::Geos.capi_supported?
  raise 'Install rgeo with CAIP support. apt install libgeos-dev, then gem install rgeo rgeo-geojson'
end

## Example usage:
#   DB.create_table? :geoms do
#     primary_key :id
#     Geometry    :geom
#   end
#
#   DB.execute "INSERT INTO geoms(geom) VALUES( ST_GeomFromText('POINT(-71.060316 48.432044)', 4326));"
#
#   gs = DB[:geoms].all
#
#   # Output as WKB format
#   Sequel::Postgres::GeoDatabaseMethods::Geometry.to_json_format = :wkb
#   p gs[0].to_json
#
#   # Output as GeoJSON format
#   Sequel::Postgres::GeoDatabaseMethods::Geometry.to_json_format = :geojson
#   p gs[0].to_json
module Sequel
  module Postgres
    module GeoDatabaseMethods
      class Geometry
        # 4326 (WGS 84), 3857 (Web Mercator):
        FACTORY = RGeo::Geos.factory(:native_interface => :capi)
        PARSER = RGeo::WKRep::WKBParser.new(FACTORY, support_ewkb: true, default_srid: 4326)

        class << self
          attr_accessor :to_json_format # wkb, geojson
        end
        attr_accessor :wkb_string
        def initialize(wkb_string)
          @wkb_string = wkb_string
        end

        def to_json(*a)
          @wkb_string.to_json
        end

        def as_json
          @wkb_string.to_s
        end
      end

      def self.extended(db)
        db.instance_exec do
          extend_datasets(GeoDatasetMethods)

          geom_new = Geometry.method(:new)
          add_conversion_proc 18046, geom_new
          @schema_type_classes[:geometry] = Geometry
        end
      end

      private

      def schema_column_type(db_type)
        db_type == 'geometry' ? Geometry : super
      end

      def typecast_value_geometry(value)
        value
      end

      module GeoDatasetMethods

        private
        def literal_other_append(sql, value)
          if value.is_a?(Geometry)
            sql << "ST_SetSRID(ST_GeomFromWKB('\\x#{value.wkb_string}'),4326)"
          else
            super
          end
        end

      end
    end
  end

  Database.register_extension(:pg_geo, Postgres::GeoDatabaseMethods)
end
Geometry = Sequel::Postgres::GeoDatabaseMethods::Geometry

# DB.extension :pg_geo
Sequel::Database.after_initialize do |db|
  pr = Sequel.synchronize { Sequel::Database::EXTENSIONS[:pg_geo] }
  db.instance_eval { pr&.call(self) if !@loaded_extensions.include?(:pg_geo) && @loaded_extensions << :pg_geo }
end
