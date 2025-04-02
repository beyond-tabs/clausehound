CREATE TABLE IF NOT EXISTS named_entity_types (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS named_entities (
  id CHAR(36) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  keywords JSON NOT NULL,
  weight FLOAT NOT NULL,
  named_entity_type_id INT,
  FOREIGN KEY (named_entity_type_id) REFERENCES named_entity_types(id)
);

INSERT INTO named_entity_types (id, name) VALUES (1, 'QUALIFIER');

INSERT INTO named_entities (id, name, keywords, weight, named_entity_type_id)
VALUES (
  'fa1ae2c8-2484-41a3-85e4-00cc9f28b790',
  'avionics',
  '[\"avionics\"]',
  10.0,
  1
);
