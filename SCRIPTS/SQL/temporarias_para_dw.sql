-- CARGA DE DADOS DAS TEMPORÁRIAS PARA O DW

-- DIM MUNICÍPIO
INSERT INTO dim_municipio (sk_municipio, cd_ibge, nm_municipio, nm_regiao)
SELECT 
    ROWNUM AS sk_municipio,
    cd_ibge,
    nm_municipio,
    nm_regiao
FROM (
    SELECT
        TRIM(SUBSTR(t.municipio_raw, 1, 6))AS cd_ibge,
        TRIM(SUBSTR(t.municipio_raw, 8))AS nm_municipio,
        d.regiao AS nm_regiao
    FROM (
        SELECT DISTINCT municipio_raw
        FROM temp_dataSUS
        WHERE REGEXP_LIKE(municipio_raw, '^\d{6}')
    ) t
    LEFT JOIN temp_densidade d
        ON UPPER(TRANSLATE(TRIM(d.municipio),
             'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
             'AAAAAAEEEEIIIIOOOOOUUUUCAAAAAAEEEEIIIIOOOOOUUUUC'))
         = UPPER(TRIM(SUBSTR(t.municipio_raw, 8)))
);
COMMIT;


-- DIM ESTAÇÃO
INSERT INTO dim_estacao (sk_estacao, cd_estacao, nm_estacao, tp_estacao, cd_situacao, latitude, longitude, altitude)
SELECT 
    ROWNUM AS sk_estacao,
    cd_estacao, 
    dc_nome, 
    tp_estacao, 
    cd_situacao,
    latitude, 
    longitude, 
    altitude
FROM (
    SELECT
        j.cd_estacao, j.dc_nome, j.tp_estacao, j.cd_situacao,
        TO_NUMBER(j.vl_lat, '99999.99999999', 'NLS_NUMERIC_CHARACTERS=''.,''') AS latitude,
        TO_NUMBER(j.vl_lon, '99999.99999999', 'NLS_NUMERIC_CHARACTERS=''.,''') AS longitude,
        TO_NUMBER(j.vl_alt, '99999.99', 'NLS_NUMERIC_CHARACTERS=''.,''') AS altitude
    FROM temp_estacoes_json s,
         JSON_TABLE(s.conteudo, '$[*]'
             COLUMNS (
                 cd_estacao VARCHAR2(20) PATH '$.CD_ESTACAO',
                 dc_nome VARCHAR2(100) PATH '$.DC_NOME',
                 sg_estado VARCHAR2(5) PATH '$.SG_ESTADO',
                 tp_estacao VARCHAR2(30) PATH '$.TP_ESTACAO',
                 cd_situacao VARCHAR2(30) PATH '$.CD_SITUACAO',
                 vl_lat VARCHAR2(20) PATH '$.VL_LATITUDE',
                 vl_lon VARCHAR2(20) PATH '$.VL_LONGITUDE',
                 vl_alt VARCHAR2(20) PATH '$.VL_ALTITUDE'
             )
         ) j
    WHERE j.sg_estado = 'PR'
);
COMMIT;


-- DIM CLIMA
INSERT INTO dim_clima (sk_clima, sk_estacao, sk_tempo, temp_max_anual, temp_min_anual, temp_med_anual, umidade_med_anual, precipitacao_total, dias_chuva)
SELECT 
    ROWNUM AS sk_clima,
    sk_estacao, 
    sk_tempo, 
    temp_max_anual, 
    temp_min_anual, 
    temp_med_anual, 
    umidade_med_anual, 
    precipitacao_total, 
    dias_chuva
FROM (
    SELECT
        e.sk_estacao,
        t.sk_tempo,
        MAX(c.temp_max_c) AS temp_max_anual,
        MIN(c.temp_min_c) AS temp_min_anual,
        ROUND(AVG(c.temp_med_c), 2) AS temp_med_anual,
        ROUND(AVG(c.umidade_med_pct), 2) AS umidade_med_anual,
        ROUND(SUM(NVL(c.precipitacao_mm, 0)), 2) AS precipitacao_total,
        COUNT(CASE WHEN c.precipitacao_mm > 0 THEN 1 END) AS dias_chuva
    FROM temp_clima c
    JOIN dim_estacao e ON e.cd_estacao = c.codigo_estacao
    JOIN dim_tempo t ON t.ano = c.ano
    GROUP BY e.sk_estacao, t.sk_tempo
);
COMMIT;


-- DIM SOCIOECONÔMICO
INSERT INTO dim_socioeconomico (sk_socioeconomico, sk_municipio, sk_tempo, pib_per_capita, pib_total, dens_demografica)
SELECT 
    ROWNUM AS sk_socioeconomico,
    sk_municipio, 
    sk_tempo, 
    pib_per_capita, 
    pib_total, 
    dens_demografica
FROM (
    SELECT
        m.sk_municipio,
        t.sk_tempo,
        CASE t.ano
            WHEN 2018 THEN TO_NUMBER(NULLIF(x.per_capita_2018,''), '9999999')
            WHEN 2019 THEN TO_NUMBER(NULLIF(x.per_capita_2019,''), '9999999')
            WHEN 2020 THEN TO_NUMBER(NULLIF(x.per_capita_2020,''), '9999999')
            WHEN 2021 THEN TO_NUMBER(NULLIF(x.per_capita_2021,''), '9999999')
            WHEN 2022 THEN TO_NUMBER(NULLIF(x.per_capita_2022,''), '9999999')
            WHEN 2023 THEN TO_NUMBER(NULLIF(x.per_capita_2023,''), '9999999')
        END AS pib_per_capita,
        CASE t.ano
            WHEN 2018 THEN TO_NUMBER(NULLIF(x.pib_total_2018,''), '9999999999999')
            WHEN 2019 THEN TO_NUMBER(NULLIF(x.pib_total_2019,''), '9999999999999')
            WHEN 2020 THEN TO_NUMBER(NULLIF(x.pib_total_2020,''), '9999999999999')
            WHEN 2021 THEN TO_NUMBER(NULLIF(x.pib_total_2021,''), '9999999999999')
            WHEN 2022 THEN TO_NUMBER(NULLIF(x.pib_total_2022,''), '9999999999999')
            WHEN 2023 THEN TO_NUMBER(NULLIF(x.pib_total_2023,''), '9999999999999')
        END AS pib_total,
        CASE t.ano
            WHEN 2018 THEN d.dens_2018
            WHEN 2019 THEN d.dens_2019
            WHEN 2020 THEN d.dens_2020
            WHEN 2021 THEN d.dens_2021
            WHEN 2022 THEN d.dens_2022
            WHEN 2023 THEN d.dens_2023
        END AS dens_demografica
    FROM dim_municipio m
    CROSS JOIN dim_tempo t
    LEFT JOIN (
        SELECT x2.*
        FROM temp_pib_xml p,
             XMLTABLE('/pib_municipios/municipio'
                      PASSING p.conteudo
                      COLUMNS
                        municipio      VARCHAR2(200) PATH 'municipio',
                        per_capita_2018 VARCHAR2(20) PATH 'per_capita_2018',
                        per_capita_2019 VARCHAR2(20) PATH 'per_capita_2019',
                        per_capita_2020 VARCHAR2(20) PATH 'per_capita_2020',
                        per_capita_2021 VARCHAR2(20) PATH 'per_capita_2021',
                        per_capita_2022 VARCHAR2(20) PATH 'per_capita_2022',
                        per_capita_2023 VARCHAR2(20) PATH 'per_capita_2023',
                        pib_total_2018  VARCHAR2(20) PATH 'pib_total_2018',
                        pib_total_2019  VARCHAR2(20) PATH 'pib_total_2019',
                        pib_total_2020  VARCHAR2(20) PATH 'pib_total_2020',
                        pib_total_2021  VARCHAR2(20) PATH 'pib_total_2021',
                        pib_total_2022  VARCHAR2(20) PATH 'pib_total_2022',
                        pib_total_2023  VARCHAR2(20) PATH 'pib_total_2023'
             ) x2
        WHERE x2.municipio NOT IN ('Estado do Paraná', 'MUNICÍPIOS')
    ) x ON UPPER(TRANSLATE(x.municipio,
             'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
             'AAAAAAEEEEIIIIOOOOOUUUUCAAAAAAEEEEIIIIOOOOOUUUUC'))
         = UPPER(m.nm_municipio)
    LEFT JOIN temp_densidade d
        ON UPPER(TRANSLATE(d.municipio,
             'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
             'AAAAAAEEEEIIIIOOOOOUUUUCAAAAAAEEEEIIIIOOOOOUUUUC'))
         = UPPER(m.nm_municipio)
);
COMMIT;


-- FATO TUBERCULOSE
INSERT INTO fato_tuberculose (sk_fat, sk_municipio, sk_tempo, sk_estacao, sk_socioeconomico, sk_clima, casos_tb)
SELECT 
    ROWNUM AS sk_fat,
    base.sk_municipio,
    base.sk_tempo,
    base.sk_estacao,
    base.sk_socioeconomico,
    base.sk_clima,
    base.casos_tb
FROM (
    SELECT
        m.sk_municipio,
        t.sk_tempo,
        de.sk_estacao,
        s.sk_socioeconomico,
        (SELECT dc.sk_clima
         FROM dim_clima dc
         JOIN dim_estacao de ON de.sk_estacao = dc.sk_estacao
         WHERE dc.sk_tempo = t.sk_tempo
         ORDER BY ABS(de.latitude - (-24.5))
         FETCH FIRST 1 ROW ONLY) AS sk_clima,
        CASE
            WHEN tb.casos_raw = '-' OR tb.casos_raw IS NULL THEN 0
            ELSE TO_NUMBER(TRIM(tb.casos_raw))
        END AS casos_tb
    FROM dim_municipio m
    JOIN dim_tempo t ON 1=1
    JOIN (
        SELECT municipio_raw, '2018' ano_str, casos_2018 casos_raw FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2019', casos_2019 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2020', casos_2020 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2021', casos_2021 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2022', casos_2022 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2023', casos_2023 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
    ) tb ON TRIM(SUBSTR(tb.municipio_raw, 1, 6)) = m.cd_ibge
         AND TO_NUMBER(tb.ano_str) = t.ano
    JOIN dim_socioeconomico s
        ON s.sk_municipio = m.sk_municipio
       AND s.sk_tempo     = t.sk_tempo
) base
WHERE base.sk_clima IS NOT NULL;
COMMIT;

-- CORREÇÃO: ASSOCIANDO CADA MUNICÍPIO COM A ESTAÇÃO MAIS PRÓXIMA

-- TABELA AUXILIAR
CREATE TABLE aux_regiao_estacao (
    nm_regiao  VARCHAR2(200),
    cd_estacao VARCHAR2(20)
);

INSERT INTO aux_regiao_estacao VALUES ('RGI de Apucarana',                             'A835');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Campo Mourão',                          'A822');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Cascavel',                              'A820');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Cianorte',                              'A869');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Cornélio Procópio - Bandeirantes',      'A842');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Curitiba',                              'A807');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Dois Vizinhos',                         'A843');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Foz do Iguaçu',                         'A846');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Francisco Beltrão',                     'A843');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Guarapuava',                            'A823');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Ibaiti',                                'A871');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Irati',                                 'A823');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Ivaiporã',                              'A822');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Laranjeiras do Sul - Quedas do Iguaçu', 'B804');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Loanda',                                'A849');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Londrina',                              'A842');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Marechal Cândido Rondon',               'A820');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Maringá',                               'A835');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Paranacity - Colorado',                 'A835');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Paranaguá',                             'A873');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Paranavaí',                             'A850');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Pato Branco',                           'A876');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Pitanga',                               'A822');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Ponta Grossa',                          'A819');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Santo Antônio da Platina',              'A821');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Telêmaco Borba',                        'A872');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Toledo',                                'A820');
INSERT INTO aux_regiao_estacao VALUES ('RGI de Umuarama',                              'A824');
INSERT INTO aux_regiao_estacao VALUES ('RGI de União da Vitória',                      'A875');
COMMIT;

-- CORRIGINDO sk_clima NA FATO TUBERCULOSE
UPDATE fato_tuberculose f
SET f.sk_clima = (
    SELECT dc.sk_clima
    FROM dim_municipio m
    JOIN aux_regiao_estacao r ON r.nm_regiao = m.nm_regiao
    JOIN dim_estacao de ON de.cd_estacao = r.cd_estacao
    JOIN dim_clima dc ON dc.sk_estacao = de.sk_estacao
                    AND dc.sk_tempo  = f.sk_tempo
    WHERE m.sk_municipio = f.sk_municipio
)
WHERE EXISTS (
    SELECT 1
    FROM dim_municipio m
    JOIN aux_regiao_estacao r ON r.nm_regiao = m.nm_regiao
    WHERE m.sk_municipio = f.sk_municipio
);
COMMIT;

-- DEPOIS DE DAR DROP NA FATO E ADICIONAR sk_estacao e sk_fat como number, novo insert:
INSERT INTO fato_tuberculose (sk_fat, sk_municipio, sk_tempo, sk_estacao, sk_socioeconomico, sk_clima, casos_tb)
SELECT
    ROWNUM AS sk_fat,
    base.sk_municipio,
    base.sk_tempo,
    base.sk_estacao,
    base.sk_socioeconomico,
    base.sk_clima,
    base.casos_tb
FROM (
    SELECT
        m.sk_municipio,
        t.sk_tempo,
        s.sk_socioeconomico,
        de.sk_estacao,
        dc.sk_clima,
        CASE
            WHEN tb.casos_raw = '-' OR tb.casos_raw IS NULL THEN 0
            ELSE TO_NUMBER(TRIM(tb.casos_raw))
        END AS casos_tb
    FROM dim_municipio m
    JOIN dim_tempo t ON 1=1
    -- Estação correta pelo mapeamento RGI
    JOIN aux_regiao_estacao  r  ON r.nm_regiao   = m.nm_regiao
    JOIN dim_estacao         de ON de.cd_estacao = r.cd_estacao
    JOIN dim_clima           dc ON dc.sk_estacao = de.sk_estacao
                                AND dc.sk_tempo  = t.sk_tempo
    JOIN (
        SELECT municipio_raw, '2018' ano_str, casos_2018 casos_raw FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2019', casos_2019 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2020', casos_2020 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2021', casos_2021 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2022', casos_2022 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2023', casos_2023 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
    ) tb ON TRIM(SUBSTR(tb.municipio_raw, 1, 6)) = m.cd_ibge
         AND TO_NUMBER(tb.ano_str) = t.ano
    JOIN dim_socioeconomico s
        ON s.sk_municipio = m.sk_municipio
       AND s.sk_tempo     = t.sk_tempo
) base;