-- Roll back the costume-category vocabulary and detail categorisation slots.

DROP TABLE projection_costume_category;

ALTER TABLE projection_costume_detail
    DROP COLUMN subject,
    DROP COLUMN category_id,
    DROP COLUMN category_name;
