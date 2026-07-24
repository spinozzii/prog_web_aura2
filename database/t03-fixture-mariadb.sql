SET NAMES utf8mb4 COLLATE utf8mb4_bin;

DROP TABLE IF EXISTS progressivo_ricovero;
DROP TABLE IF EXISTS patologia_ricovero;
DROP TABLE IF EXISTS ricovero;
DROP TABLE IF EXISTS ospedale;
DROP TABLE IF EXISTS patologia_mortale;
DROP TABLE IF EXISTS patologia_cronica;
DROP TABLE IF EXISTS patologia;
DROP TABLE IF EXISTS cittadino;

CREATE TABLE cittadino (
    cssn VARCHAR(255) NOT NULL,
    nome VARCHAR(255) NOT NULL,
    cognome VARCHAR(255) NOT NULL,
    data_nascita DATE NOT NULL,
    luogo_nascita VARCHAR(255) NOT NULL,
    indirizzo VARCHAR(255) NOT NULL,
    PRIMARY KEY (cssn),
    CONSTRAINT cittadino_cssn_non_vuoto CHECK (CHAR_LENGTH(cssn) > 0),
    CONSTRAINT cittadino_nome_non_vuoto CHECK (CHAR_LENGTH(nome) > 0),
    CONSTRAINT cittadino_cognome_non_vuoto CHECK (CHAR_LENGTH(cognome) > 0),
    CONSTRAINT cittadino_luogo_non_vuoto CHECK (CHAR_LENGTH(luogo_nascita) > 0),
    CONSTRAINT cittadino_indirizzo_non_vuoto CHECK (CHAR_LENGTH(indirizzo) > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE patologia (
    cod VARCHAR(20) NOT NULL,
    nome VARCHAR(255) NOT NULL,
    criticita INTEGER NOT NULL,
    PRIMARY KEY (cod),
    CONSTRAINT patologia_cod_non_vuoto CHECK (CHAR_LENGTH(cod) > 0),
    CONSTRAINT patologia_nome_non_vuoto CHECK (CHAR_LENGTH(nome) > 0),
    CONSTRAINT patologia_criticita_1_5 CHECK (criticita BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE patologia_cronica (
    cod_patologia VARCHAR(20) NOT NULL,
    PRIMARY KEY (cod_patologia),
    CONSTRAINT patologia_cronica_patologia_fk
        FOREIGN KEY (cod_patologia) REFERENCES patologia (cod)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE patologia_mortale (
    cod_patologia VARCHAR(20) NOT NULL,
    PRIMARY KEY (cod_patologia),
    CONSTRAINT patologia_mortale_patologia_fk
        FOREIGN KEY (cod_patologia) REFERENCES patologia (cod)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE ospedale (
    codice VARCHAR(20) NOT NULL,
    nome VARCHAR(255) NOT NULL,
    citta VARCHAR(255) NOT NULL,
    indirizzo VARCHAR(255) NOT NULL,
    direttore_sanitario_cssn VARCHAR(255) NOT NULL,
    PRIMARY KEY (codice),
    CONSTRAINT ospedale_direttore_univoco UNIQUE (direttore_sanitario_cssn),
    CONSTRAINT ospedale_direttore_fk
        FOREIGN KEY (direttore_sanitario_cssn) REFERENCES cittadino (cssn),
    CONSTRAINT ospedale_codice_non_vuoto CHECK (CHAR_LENGTH(codice) > 0),
    CONSTRAINT ospedale_nome_non_vuoto CHECK (CHAR_LENGTH(nome) > 0),
    CONSTRAINT ospedale_citta_non_vuota CHECK (CHAR_LENGTH(citta) > 0),
    CONSTRAINT ospedale_indirizzo_non_vuoto CHECK (CHAR_LENGTH(indirizzo) > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE ricovero (
    cod_ospedale VARCHAR(20) NOT NULL,
    cod INTEGER NOT NULL,
    paziente_cssn VARCHAR(255) NOT NULL,
    data_inizio DATE NOT NULL,
    durata INTEGER NOT NULL,
    motivo VARCHAR(500) NOT NULL,
    costo DECIMAL(14, 2) NOT NULL,
    PRIMARY KEY (cod_ospedale, cod),
    CONSTRAINT ricovero_ospedale_fk
        FOREIGN KEY (cod_ospedale) REFERENCES ospedale (codice),
    CONSTRAINT ricovero_paziente_fk
        FOREIGN KEY (paziente_cssn) REFERENCES cittadino (cssn),
    CONSTRAINT ricovero_cod_positivo CHECK (cod > 0),
    CONSTRAINT ricovero_durata_valida CHECK (durata BETWEEN 1 AND 3650),
    CONSTRAINT ricovero_motivo_non_vuoto CHECK (CHAR_LENGTH(motivo) > 0),
    CONSTRAINT ricovero_costo_non_negativo CHECK (costo >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE patologia_ricovero (
    cod_ospedale VARCHAR(20) NOT NULL,
    cod_ricovero INTEGER NOT NULL,
    cod_patologia VARCHAR(20) NOT NULL,
    PRIMARY KEY (cod_ospedale, cod_ricovero, cod_patologia),
    CONSTRAINT patologia_ricovero_ricovero_fk
        FOREIGN KEY (cod_ospedale, cod_ricovero)
        REFERENCES ricovero (cod_ospedale, cod),
    CONSTRAINT patologia_ricovero_patologia_fk
        FOREIGN KEY (cod_patologia) REFERENCES patologia (cod)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE progressivo_ricovero (
    cod_ospedale VARCHAR(20) NOT NULL,
    prossimo_cod INTEGER NOT NULL,
    PRIMARY KEY (cod_ospedale),
    CONSTRAINT progressivo_ricovero_ospedale_fk
        FOREIGN KEY (cod_ospedale) REFERENCES ospedale (codice),
    CONSTRAINT progressivo_ricovero_positivo CHECK (prossimo_cod > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

INSERT INTO cittadino
    (cssn, nome, cognome, data_nascita, luogo_nascita, indirizzo)
VALUES
    ('CSSN001', 'Àlba', 'Rossi', '1900-01-01', 'Bergamo', 'Via "Roma" 1'),
    ('CSSN002', 'Bruno', 'Bianchi', '2000-02-29', 'Milano', 'Viale Europa 2'),
    ('CSSN003', 'Carla', 'Verdi', '2026-07-24', 'Lecco', 'Piazza Duomo 3');

INSERT INTO patologia (cod, nome, criticita)
VALUES
    ('P001', 'Cronica soltanto', 1),
    ('P002', 'Mortale soltanto', 5),
    ('P003', 'Cronica e mortale', 4),
    ('P004', 'Nessuna specializzazione', 2);

INSERT INTO patologia_cronica (cod_patologia)
VALUES ('P001'), ('P003');

INSERT INTO patologia_mortale (cod_patologia)
VALUES ('P002'), ('P003');

INSERT INTO ospedale
    (codice, nome, citta, indirizzo, direttore_sanitario_cssn)
VALUES
    ('H001', 'Ospedale Sant''Ànna', 'Bergamo', 'Via Salute 10', 'CSSN001'),
    ('H002', 'Clinica Nord', 'Milano', 'Via Cura 20', 'CSSN002');

INSERT INTO ricovero
    (cod_ospedale, cod, paziente_cssn, data_inizio, durata, motivo, costo)
VALUES
    ('H001', 1, 'CSSN003', '2024-02-29', 1, 'Controllo "speciale"\\giornaliero', 0.00),
    ('H001', 2, 'CSSN002', '1900-01-01', 3650, 'Terapia prolungata', 1234.50),
    ('H002', 1, 'CSSN001', '2026-07-24', 10, 'Osservazione', 99.99);

INSERT INTO patologia_ricovero
    (cod_ospedale, cod_ricovero, cod_patologia)
VALUES
    ('H001', 1, 'P001'),
    ('H001', 1, 'P003'),
    ('H001', 2, 'P002'),
    ('H002', 1, 'P004');

INSERT INTO progressivo_ricovero (cod_ospedale, prossimo_cod)
VALUES ('H001', 3), ('H002', 2);
