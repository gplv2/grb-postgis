CREATE INDEX idx_tourism ON planet_osm_polygon ("tourism");
CREATE INDEX idx_building ON planet_osm_polygon ("building");
CREATE INDEX idx_landuse ON planet_osm_polygon ("landuse");
CREATE INDEX idx_natural ON planet_osm_polygon ("natural");
CREATE INDEX idx_waterway ON planet_osm_polygon ("waterway");
CREATE INDEX idx_junction ON planet_osm_polygon ("junction");
CREATE INDEX idx_p_mm ON planet_osm_polygon ("man_made");
CREATE INDEX idx_p_lei ON planet_osm_polygon ("leisure");
CREATE INDEX idx_hw ON planet_osm_polygon ("highway");
CREATE INDEX idx_name ON planet_osm_polygon ("name");
CREATE INDEX hidx_pop ON public.planet_osm_polygon USING btree (((tags OPERATOR(public.->) 'addr:unit'::text)));
CREATE INDEX idx_ploy_amenity ON public.planet_osm_polygon USING btree (amenity);

CREATE INDEX idx_l_name ON planet_osm_line ("name");
CREATE INDEX idx_l_route ON planet_osm_line ("route");
CREATE INDEX idx_leisure ON planet_osm_line ("leisure");
CREATE INDEX idx_point_place ON planet_osm_line ("place");
CREATE INDEX idx_point_name ON planet_osm_line ("name");
CREATE INDEX idx_line_rail ON planet_osm_line ("railway");
CREATE INDEX idx_line_tunnel ON planet_osm_line ("tunnel");
CREATE INDEX idx_line_hw ON planet_osm_line ("highway");
CREATE INDEX idx_line_natural ON planet_osm_line ("natural");
CREATE INDEX idx_line_aeroway ON planet_osm_line ("aeroway");
CREATE INDEX idx_line_amenity ON planet_osm_line ("amenity");
CREATE INDEX idx_mm ON planet_osm_line ("man_made");
CREATE INDEX idx_pol_ww ON planet_osm_line ("waterway");

CREATE INDEX hidx_poi ON public.planet_osm_point USING btree (((tags OPERATOR(public.->) 'addr:unit'::text)));
CREATE INDEX idx_pp_addr1 ON public.planet_osm_point USING btree ("addr:housenumber") WHERE ("addr:housenumber" IS NOT NULL);
CREATE INDEX idx_pp_addr2 ON public.planet_osm_point USING btree ("addr:housename") WHERE ("addr:housename" IS NOT NULL);
CREATE INDEX idx_pp_building ON public.planet_osm_point USING btree (building) WHERE (building IS NOT NULL);
CREATE INDEX idx_pol_building ON public.planet_osm_line USING btree (building);

CREATE INDEX idx_pop_barier on "planet_osm_polygon" ("barrier");
CREATE INDEX idx_pol_aerialway on "planet_osm_line" ("aerialway");
CREATE INDEX idx_pol_power on "planet_osm_line" ("power");
CREATE INDEX idx_pop_leisure on "planet_osm_polygon" ("leisure");
CREATE INDEX idx_pop_boundary on "planet_osm_polygon" ("boundary");
CREATE INDEX idx_pop_admin_level on "planet_osm_polygon" ("admin_level");
CREATE INDEX idx_pop_amenity on "planet_osm_polygon" ("amenity");
CREATE INDEX idx_pol_ref on "planet_osm_line" ("ref");

CREATE INDEX idx_planet_osm_line_nobridge ON planet_osm_polygon USING gist (way) WHERE ((man_made <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) OR man_made IS NOT NULL);
CREATE INDEX idx_pop_mm_null ON planet_osm_polygon USING gist (way) WHERE (man_made IS NOT NULL);
CREATE INDEX idx_pop_no_bridge ON planet_osm_polygon USING gist (way) WHERE (bridge <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_pop_hw_null ON planet_osm_polygon USING gist (way) WHERE (highway IS NOT NULL);
CREATE INDEX idx_pop_no_hw ON planet_osm_polygon USING gist (way) WHERE (highway <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_pop_no_b ON planet_osm_polygon USING gist (way) WHERE (building <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_pop_b_null ON planet_osm_polygon USING gist (way) WHERE (building IS NOT NULL);


-- move indexes to tablespace if you have them
-- ALTER INDEX ALL IN TABLESPACE pg_default OWNED BY "grb-data" SET TABLESPACE indexspace;
