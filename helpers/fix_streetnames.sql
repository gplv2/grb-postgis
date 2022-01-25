-- Urbis
UPDATE planet_osm_polygon SET "addr:street"='Rue de l''Équerre - Winkelhaakstraat' WHERE "addr:street" = 'Rue de l''Equerre - Winkelhaakstraat' AND "source:geometry:entity"='Urbis';
UPDATE planet_osm_polygon SET "addr:street:fr"='Rue de l''Équerre' WHERE "addr:street:fr" = 'Rue de l''Equerre' AND "source:geometry:entity"='Urbis';
UPDATE planet_osm_polygon SET "addr:street"='Rue Docteur Élie Lambotte - Dokter Élie Lambottestraat' WHERE "addr:street" = 'Rue Docteur Elie Lambotte - Dokter Elie Lambottestraat' AND "source:geometry:entity"='Urbis';
UPDATE planet_osm_polygon SET "addr:street:fr"='Rue Docteur Élie Lambotte' WHERE "addr:street:fr" = 'Rue Docteur Elie Lambotte' AND "source:geometry:entity"='Urbis';
UPDATE planet_osm_polygon SET "addr:street"='Rue Ducale - Hertogstraat' , "addr:street:nl"='Hertogstraat' WHERE "addr:street" = 'Rue Ducale - Hertogsstraat' AND "source:geometry:entity"='Urbis';
UPDATE planet_osm_polygon SET "addr:street"='Rue de la Cigogne - Ooievaarstraat' , "addr:street:nl"='Ooievaarstraat' WHERE "addr:street" = 'Rue de la Cigogne - Ooievaarsstraat' AND "source:geometry:entity"='Urbis';
UPDATE planet_osm_polygon SET "addr:street"='Rue des Œillets - Anjelierenstraat' , "addr:street:fr"='Rue des Œillets' WHERE "addr:street" = 'Rue des Oeillets - Anjelierenstraat' AND "source:geometry:entity"='Urbis';

-- Gbg 
UPDATE planet_osm_polygon SET "addr:street"='Rue des Œillets - Anjelierenstraat' , "addr:street:fr"='Rue des Œillets' WHERE "addr:street" = 'Rue des Oeillets - Anjelierenstraat' AND "source:geometry:entity"='Gbg';
