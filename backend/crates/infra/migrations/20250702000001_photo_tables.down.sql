-- Rollback photo-lifecycle projection tables (change: add-costume-photo-storage).

DROP TABLE IF EXISTS projection_photo_gc_run;
DROP TABLE IF EXISTS projection_photo_variant;
DROP TABLE IF EXISTS projection_photo;
