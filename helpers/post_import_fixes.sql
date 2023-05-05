-- indexes :
CREATE INDEX index_source_date ON public.planet_osm_polygon USING btree ("source:geometry:date") WHERE ("source:geometry:date" IS NOT NULL);
CREATE INDEX index_addr_fr ON public.planet_osm_polygon USING btree (osm_id) WHERE (("addr:street:fr" IS NOT NULL) AND ("source:geometry:entity" = 'Urbis'::text));
CREATE INDEX index_addr_nl ON public.planet_osm_polygon USING btree (osm_id) WHERE (("addr:street:nl" IS NOT NULL) AND ("source:geometry:entity" = 'Urbis'::text));
CREATE INDEX index_addr ON public.planet_osm_polygon USING btree (osm_id) WHERE ("addr:street" IS NOT NULL);
CREATE INDEX index_building ON public.planet_osm_polygon USING btree (building);

-- post fixes - probably need to be fixed a lot earlier in the processing, especially the first one is a mistake at import handling
UPDATE planet_osm_polygon SET "source:geometry:version"= CAST(tags->'VERSIONsource:geometry:oidn' AS INTEGER) where tags->'VERSIONsource:geometry:oidn' IS NOT NULL;
UPDATE planet_osm_polygon SET "addr:street:fr" = split_part("addr:street",' - ',1), "addr:street:nl" = split_part("addr:street",' - ',2) where "source:geometry:entity"='Urbis' AND "addr:street" IS NOT NULL AND ("addr:street:nl" IS NULL AND "addr:street:fr" IS NULL );
UPDATE planet_osm_polygon SET way=ST_centroid(way) WHERE man_made='mast';
UPDATE planet_osm_polygon SET "addr:street" = upper(left("addr:street", 1)) || right("addr:street", -1) WHERE "addr:street" is not null AND "addr:street" <> upper(left("addr:street", 1)) || right("addr:street", -1) AND "addr:street" NOT IN ('von Asten-Straße','von-Dhaem-Strasse','von-Montigny-Straße','von-Orley-Straße','t Zand','be-MINE') AND position('''' IN "addr:street") <> 2;
UPDATE planet_osm_polygon SET "addr:street:nl" = upper(left("addr:street:nl", 1)) || right("addr:street:nl", -1) WHERE "addr:street:nl" is not null AND "addr:street:nl" <> upper(left("addr:street:nl", 1)) || right("addr:street:nl", -1) AND "addr:street:nl" NOT IN ('von Asten-Straße','von-Dhaem-Strasse','von-Montigny-Straße','von-Orley-Straße','t Zand','be-MINE') AND position('''' IN "addr:street:nl") <> 2 AND "addr:street:fr" IS NOT NULL;
UPDATE planet_osm_polygon SET "addr:street:fr" = upper(left("addr:street:fr", 1)) || right("addr:street:fr", -1) WHERE "addr:street:fr" is not null AND "addr:street:fr" <> upper(left("addr:street:fr", 1)) || right("addr:street:fr", -1) AND "addr:street:fr" NOT IN ('von Asten-Straße','von-Dhaem-Strasse','von-Montigny-Straße','von-Orley-Straße','t Zand','be-MINE') AND position('''' IN "addr:street:fr") <>2 AND "addr:street:fr" IS NOT NULL;
UPDATE planet_osm_polygon SET "source:geometry:date"= REPLACE("source:geometry:date",'/','-')  where "source:geometry:entity" IN ('Gba','Knw','Gbg') and "source:geometry:date" IS NOT NULL;
