#!/bin/sh 


SELECT ' ALTER TABLE ' || schemaname || '.' || tablename || ' SET TABLESPACE pg_default;' FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');

ALTER TABLE public.planet_osm_line SET TABLESPACE pg_default;
ALTER TABLE public.spatial_ref_sys SET TABLESPACE pg_default;
ALTER TABLE topology.topology SET TABLESPACE pg_default;
ALTER TABLE topology.layer SET TABLESPACE pg_default;
ALTER TABLE public.planet_osm_polygon SET TABLESPACE pg_default;
ALTER TABLE public.planet_osm_roads SET TABLESPACE pg_default;
ALTER TABLE public.planet_osm_nodes SET TABLESPACE pg_default;
ALTER TABLE public.planet_osm_ways SET TABLESPACE pg_default;
ALTER TABLE public.planet_osm_rels SET TABLESPACE pg_default;
ALTER TABLE public.planet_osm_point SET TABLESPACE pg_default;

ALTER DATABASE grb_temp SET TABLESPACE dbspace;

