ALTER TABLE planet_osm_line ALTER COLUMN way TYPE geometry(LineString,900913) USING ST_Transform(way,900913);
ALTER TABLE planet_osm_polygon ALTER COLUMN way TYPE geometry(Geometry,900913) USING ST_Transform(way,900913);
ALTER TABLE planet_osm_point ALTER COLUMN way TYPE geometry(Point,900913) USING ST_Transform(way,900913);
