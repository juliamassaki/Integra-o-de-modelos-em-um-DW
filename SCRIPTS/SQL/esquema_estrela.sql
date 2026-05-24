
-- ESQUEMA ESTRELA

-- DIM TEMPO
CREATE TABLE dim_tempo (
    sk_tempo INT PRIMARY KEY,
    ano NUMBER(4) NOT NULL,
    pandemia  CHAR(1)
);

INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (1, 2018, 'N');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (2, 2019, 'N');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (3, 2020, 'S');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (4, 2021, 'S');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (5, 2022, 'S');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (6, 2023, 'N');
COMMIT;

-- DIM MUNICÍPIO
CREATE TABLE dim_municipio (
    sk_municipio INT PRIMARY KEY,
    cd_ibge VARCHAR2(10) NOT NULL,
    nm_municipio VARCHAR2(100) NOT NULL,
    nm_regiao VARCHAR2(200)
);

-- DIM ESTAÇÃO
CREATE TABLE dim_estacao (
    sk_estacao INT PRIMARY KEY,
    cd_estacao VARCHAR2(20),
    nm_estacao VARCHAR2(100),
    tp_estacao VARCHAR2(30),
    cd_situacao VARCHAR2(30),
    latitude NUMBER(12,8),
    longitude NUMBER(12,8),
    altitude NUMBER(8,2)
);

-- DIM CLIMA (agregado anual por estação)
CREATE TABLE dim_clima (
    sk_clima INT PRIMARY KEY,
    sk_estacao INT NOT NULL,
    sk_tempo INT NOT NULL,
    temp_max_anual NUMBER(6,2),
    temp_min_anual NUMBER(6,2),
    temp_med_anual NUMBER(6,2),
    umidade_med_anual NUMBER(6,2),
    precipitacao_total NUMBER(10,2),
    dias_chuva NUMBER(5),
    CONSTRAINT fk_clima_est FOREIGN KEY(sk_estacao) REFERENCES dim_estacao(sk_estacao),
    CONSTRAINT fk_clima_temp FOREIGN KEY(sk_tempo) REFERENCES dim_tempo(sk_tempo)
);

-- DIM SOCIOECONÔMICO
CREATE TABLE dim_socioeconomico (
    sk_socioeconomico INT PRIMARY KEY,
    sk_municipio INT NOT NULL,
    sk_tempo INT NOT NULL,
    pib_per_capita NUMBER(15,2),
    pib_total NUMBER(20),
    dens_demografica NUMBER(10,2),
    CONSTRAINT fk_socio_mun FOREIGN KEY(sk_municipio)REFERENCES dim_municipio(sk_municipio),
    CONSTRAINT fk_socio_temp FOREIGN KEY(sk_tempo)REFERENCES dim_tempo(sk_tempo)
);

-- FATO TUBERCULOSE
CREATE TABLE fato_tuberculose (
    sk_fat number(10) PRIMARY KEY,
    sk_municipio INT NOT NULL,
    sk_tempo INT NOT NULL,
    sk_estacao INT NOT NULL,
    sk_socioeconomico INT,
    sk_clima INT,
    casos_tb NUMBER(6),
    CONSTRAINT fk_fat_mun FOREIGN KEY(sk_municipio)REFERENCES dim_municipio(sk_municipio),
    CONSTRAINT fk_fat_tempo FOREIGN KEY(sk_tempo)REFERENCES dim_tempo(sk_tempo),
    CONSTRAINT fk_fat_estacao FOREIGN KEY(sk_estacao)REFERENCES dim_estacao(sk_estacao),
    CONSTRAINT fk_fat_socio FOREIGN KEY(sk_socioeconomico)REFERENCES dim_socioeconomico(sk_socioeconomico),
    CONSTRAINT fk_fat_clima FOREIGN KEY(sk_clima)REFERENCES dim_clima(sk_clima)
);
